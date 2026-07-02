#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block_call_return_contract.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
INT_WRAPPER="$TMP_DIR/int_wrapper.hir"

cat > "$SRC" <<'CR'
struct PhaseBox
  def disabled?
    false
  end

  def phase(name : Int32, &)
    return yield unless disabled?
    result = yield
    result
  end
end

box = PhaseBox.new
box.phase(1) { nil }
value = box.phase(2) { 7 }
value
CR

ADAMAS_DISABLE_INLINE_YIELD=1 ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 \
  "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

HIR="$OUT.hir"
if [[ ! -f "$HIR" ]]; then
  echo "missing HIR output" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! rg -q 'PhaseBox#phase[$]Int32_block' "$HIR"; then
  echo "missing shared PhaseBox#phase Int32 block wrapper" >&2
  rg -n 'PhaseBox#phase' "$HIR" >&2 || true
  exit 1
fi

if ! rg -q 'PhaseBox#phase[$]Int32_Int32_block' "$HIR"; then
  echo "missing return-shaped PhaseBox#phase Int32->Int32 block wrapper" >&2
  rg -n 'PhaseBox#phase' "$HIR" >&2 || true
  exit 1
fi

awk '
  /^func @PhaseBox#phase[$]Int32_Int32_block/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$HIR" > "$INT_WRAPPER"

if [[ ! -s "$INT_WRAPPER" ]]; then
  echo "could not extract return-shaped wrapper body" >&2
  rg -n 'func @PhaseBox#phase' "$HIR" >&2 || true
  exit 1
fi

if grep -Eq '= yield : 0$' "$INT_WRAPPER"; then
  echo "return-shaped assigned-tail wrapper still yields Void" >&2
  cat "$INT_WRAPPER" >&2
  exit 1
fi

if ! grep -Eq '= yield : [1-9][0-9]*$' "$INT_WRAPPER"; then
  echo "return-shaped assigned-tail wrapper does not yield a non-void value" >&2
  cat "$INT_WRAPPER" >&2
  exit 1
fi

if ! grep -Eq 'call %[^[:space:]]*PhaseBox#phase[$]Int32_Int32_block\([^)]*\) : [1-9][0-9]* with_block' "$HIR"; then
  echo "value-return callsite does not call the return-shaped wrapper with a non-void result" >&2
  rg -n 'call .*PhaseBox#phase' "$HIR" >&2 || true
  exit 1
fi

echo "block_call_return_contract_assigned_tail_no_prelude_ok"
