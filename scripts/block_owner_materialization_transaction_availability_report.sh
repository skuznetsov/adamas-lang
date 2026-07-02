#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  echo "env: TIMEOUT=240 MEM_MB=8192" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TIMEOUT="${TIMEOUT:-240}"
MEM_MB="${MEM_MB:-8192}"
mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/block-owner-materialization.XXXXXX")"
OUT="$TMP_DIR/adamas_self"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

set +e
ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "$ROOT_DIR/src/adamas.cr" -o "$OUT" --emit llvm-ir --no-link >"$LOG" 2>&1
compiler_rc=$?
set -e

if [[ $compiler_rc -ne 0 ]]; then
  echo "FAIL: compiler self-IR build failed (status $compiler_rc)" >&2
  tail -100 "$LOG" >&2 || true
  exit 2
fi

LL="${OUT}.ll"
if [[ ! -f "$LL" ]]; then
  echo "FAIL: expected LLVM IR was not written: $LL" >&2
  tail -100 "$LOG" >&2 || true
  exit 2
fi

if ! grep -q '^\[MAT_TX\]' "$LOG"; then
  echo "FAIL: no [MAT_TX] materialization transaction rows emitted" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q '^\[MAT_EMIT\]' "$LOG"; then
  echo "FAIL: no [MAT_EMIT] materialization emission rows emitted" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

summary="$(
  awk '
    function field(name,    i, p) {
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p > 0 && substr($i, 1, p - 1) == name) {
          return substr($i, p + 1)
        }
      }
      return ""
    }

    function is_block_owner_setter_symbol(symbol) {
      return symbol ~ /Hash\(UInt64,%20Adamas::HIR::AstToHir::BlockOwner\)#\[\]=/
    }

    function is_block_owner_setter_emit(symbol) {
      return symbol ~ /Hash\$LUInt64\$C\$_Adamas\$CCHIR\$CCAstToHir\$CCBlockOwner\$R\$H\$IDXS/
    }

    /^\[MAT_TX\]/ {
      tx = field("tx")
      requested = field("requested")
      target = field("target")
      body = field("body_symbol")
      call = field("call_symbol_hint")
      status = field("identity_status")
      relation = field("symbol_relation")
      phase = field("phase")

      if (is_block_owner_setter_symbol(requested) ||
          is_block_owner_setter_symbol(target) ||
          is_block_owner_setter_symbol(body) ||
          is_block_owner_setter_symbol(call)) {
        tx_rows++
        tx_seen[tx] = 1
        if (status == "exact") exact_tx++
        if (relation == "all_equal") all_equal_tx++
        if (phase == "instance_method") instance_tx++
        if (body == call && body != "") body_eq_call_tx++
        if (sample_tx == "") sample_tx = $0
      }
    }

    /^\[MAT_EMIT\]/ {
      tx = field("tx")
      emitted = field("emitted")
      body_present = field("body_present")
      kind = field("kind")

      if (is_block_owner_setter_emit(emitted)) {
        emit_rows++
        if (body_present == "1") body_present_rows++
        if (body_present == "0") body_missing_rows++
        if (kind == "call") call_emit_rows++
        if (tx in tx_seen) joined_emit_rows++
        if (sample_emit == "") sample_emit = $0
      }
    }

    END {
      printf("tx_rows=%d\n", tx_rows + 0)
      printf("exact_tx=%d\n", exact_tx + 0)
      printf("all_equal_tx=%d\n", all_equal_tx + 0)
      printf("instance_tx=%d\n", instance_tx + 0)
      printf("body_eq_call_tx=%d\n", body_eq_call_tx + 0)
      printf("emit_rows=%d\n", emit_rows + 0)
      printf("call_emit_rows=%d\n", call_emit_rows + 0)
      printf("joined_emit_rows=%d\n", joined_emit_rows + 0)
      printf("body_present_rows=%d\n", body_present_rows + 0)
      printf("body_missing_rows=%d\n", body_missing_rows + 0)
      if (sample_tx != "") printf("sample_tx=%s\n", sample_tx)
      if (sample_emit != "") printf("sample_emit=%s\n", sample_emit)
    }
  ' "$LOG"
)"

value_for() {
  local key="$1"
  printf '%s\n' "$summary" | awk -F= -v k="$key" '$1 == k { print $2; exit }'
}

tx_rows="$(value_for tx_rows)"
exact_tx="$(value_for exact_tx)"
all_equal_tx="$(value_for all_equal_tx)"
instance_tx="$(value_for instance_tx)"
body_eq_call_tx="$(value_for body_eq_call_tx)"
emit_rows="$(value_for emit_rows)"
call_emit_rows="$(value_for call_emit_rows)"
joined_emit_rows="$(value_for joined_emit_rows)"
body_present_rows="$(value_for body_present_rows)"
body_missing_rows="$(value_for body_missing_rows)"

stub_defs="$(
  awk '
    /^define .*Hash.*UInt64.*BlockOwner.*IDXS/ {
      in_def = 1
      body = $0 "\n"
      next
    }
    in_def {
      body = body $0 "\n"
      if ($0 == "}") {
        if (body ~ /STUB CALLED/ || body ~ /@abort/) {
          stubs++
        } else {
          real++
        }
        in_def = 0
        body = ""
      }
    }
    END {
      printf("real=%d stubs=%d\n", real + 0, stubs + 0)
    }
  ' "$LL"
)"

real_defs="$(printf '%s\n' "$stub_defs" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^real=/) { sub(/^real=/, "", $i); print $i } }')"
stub_def_count="$(printf '%s\n' "$stub_defs" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^stubs=/) { sub(/^stubs=/, "", $i); print $i } }')"

echo "[BLOCK_OWNER_MAT_AVAIL] compiler=$COMPILER tx_rows=$tx_rows exact_tx=$exact_tx all_equal_tx=$all_equal_tx instance_tx=$instance_tx body_eq_call_tx=$body_eq_call_tx emit_rows=$emit_rows call_emit_rows=$call_emit_rows joined_emit_rows=$joined_emit_rows body_present_rows=$body_present_rows body_missing_rows=$body_missing_rows real_defs=$real_defs stub_defs=$stub_def_count"

if (( tx_rows < 1 )); then
  echo "FAIL: no BlockOwner Hash#[]= [MAT_TX] transaction row" >&2
  exit 1
fi

if (( exact_tx < 1 || all_equal_tx < 1 || instance_tx < 1 || body_eq_call_tx < 1 )); then
  echo "FAIL: BlockOwner Hash#[]= transaction does not prove exact all-equal instance body/call identity" >&2
  printf '%s\n' "$summary" | sed -n '/^sample_tx=/p' >&2
  exit 1
fi

if (( emit_rows < 1 || call_emit_rows < 1 || joined_emit_rows < 1 )); then
  echo "FAIL: BlockOwner Hash#[]= emission is missing or is not joined to its transaction" >&2
  printf '%s\n' "$summary" | sed -n '/^sample_emit=/p' >&2
  exit 1
fi

if (( body_missing_rows > 0 || body_present_rows < 1 )); then
  echo "FAIL: BlockOwner Hash#[]= emission has missing body visibility" >&2
  printf '%s\n' "$summary" | sed -n '/^sample_emit=/p' >&2
  exit 1
fi

if (( real_defs < 1 )); then
  echo "FAIL: no non-stub Hash(UInt64, BlockOwner)#[]= LLVM body found" >&2
  exit 1
fi

if (( stub_def_count > 0 )); then
  echo "FAIL: Hash(UInt64, BlockOwner)#[]= still has an abort stub body" >&2
  exit 1
fi

echo "PASS: BlockOwner Hash#[]= materialization transaction availability is joined and body-present"
