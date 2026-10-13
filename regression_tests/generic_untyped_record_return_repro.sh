#!/usr/bin/env bash
# Regression guard for exact return ownership of an untyped generic factory.
# Each source exercises the same factory with a different first specialization;
# the HIR call and field types must remain owned by their exact Info(T) target.
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [compiler]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TIMEOUT_SEC="${GENERIC_RETURN_TIMEOUT_SEC:-120}"
MEM_MB="${GENERIC_RETURN_MEM_MB:-4096}"
CHECK_HIR="${GENERIC_RETURN_CHECK_HIR:-1}"

if [[ "$CHECK_HIR" != "0" && "$CHECK_HIR" != "1" ]]; then
  echo "GENERIC_RETURN_CHECK_HIR must be 0 or 1" >&2
  exit 2
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_untyped_record_return.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORKDIR" >&2
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "compiler is not executable: $COMPILER" >&2
  exit 2
fi

extract_function() {
  local file="$1"
  local prefix="$2"
  awk -v prefix="$prefix" '
    !inside && index($0, prefix) == 1 { inside = 1 }
    inside && seen && /^func @/ { exit }
    inside { print; seen = 1 }
  ' "$file"
}

function_return_id() {
  awk '{
    for (i = 1; i <= NF; i++) {
      if ($i == "->") {
        print $(i + 1)
        exit
      }
    }
  }'
}

call_return_id() {
  local function_text="$1"
  local method_pattern="$2"
  awk -v method_pattern="$method_pattern" '
    index($0, method_pattern) {
      for (i = 1; i <= NF; i++) {
        if ($i == ":") {
          print $(i + 1)
          exit
        }
      }
    }
  ' <<<"$function_text"
}

check_hir() {
  local hir="$1"
  local order="$2"
  local make_u32_header make_u64_header read_u32_header read_u64_header
  make_u32_header="$(awk '/^func @make\$UInt32\(/ { print; exit }' "$hir")"
  make_u64_header="$(awk '/^func @make\$UInt64\(/ { print; exit }' "$hir")"
  read_u32_header="$(awk '/^func @read_u32\(\)/ { print; exit }' "$hir")"
  read_u64_header="$(awk '/^func @read_u64\(\)/ { print; exit }' "$hir")"

  if [[ -z "$make_u32_header" || -z "$make_u64_header" ||
        -z "$read_u32_header" || -z "$read_u64_header" ]]; then
    echo "[$order] missing exact factory/read function in HIR" >&2
    return 1
  fi

  local make_u32_id make_u64_id read_u32_id read_u64_id
  make_u32_id="$(function_return_id <<<"$make_u32_header")"
  make_u64_id="$(function_return_id <<<"$make_u64_header")"
  read_u32_id="$(function_return_id <<<"$read_u32_header")"
  read_u64_id="$(function_return_id <<<"$read_u64_header")"

  if [[ -z "$make_u32_id" || -z "$make_u64_id" ||
        -z "$read_u32_id" || -z "$read_u64_id" ||
        "$make_u32_id" == "$make_u64_id" ]]; then
    echo "[$order] exact factory return ids are missing or collapsed" >&2
    return 1
  fi

  if ! grep -Fq "Struct Info(UInt32)" "$hir" ||
     ! grep -Fq "Struct Info(UInt64)" "$hir"; then
    echo "[$order] specialized Info descriptors are missing" >&2
    return 1
  fi

  local read_u32_body read_u64_body u32_call_id u64_call_id u32_field_id u64_field_id
  read_u32_body="$(extract_function "$hir" 'func @read_u32()')"
  read_u64_body="$(extract_function "$hir" 'func @read_u64()')"
  u32_call_id="$(call_return_id "$read_u32_body" 'call make$UInt32(')"
  u64_call_id="$(call_return_id "$read_u64_body" 'call make$UInt64(')"
  u32_field_id="$(awk '/field_get/ { for (i = 1; i <= NF; i++) if ($i == ":") { print $(i + 1); exit } }' <<<"$read_u32_body")"
  u64_field_id="$(awk '/field_get/ { for (i = 1; i <= NF; i++) if ($i == ":") { print $(i + 1); exit } }' <<<"$read_u64_body")"

  if [[ "$u32_call_id" != "$make_u32_id" || "$u64_call_id" != "$make_u64_id" ||
        "$u32_field_id" != "$read_u32_id" || "$u64_field_id" != "$read_u64_id" ]]; then
    echo "[$order] HIR exact ownership mismatch" >&2
    echo "  make_u32=$make_u32_id make_u64=$make_u64_id read_u32=$read_u32_id read_u64=$read_u64_id" >&2
    echo "  calls=$u32_call_id/$u64_call_id fields=$u32_field_id/$u64_field_id" >&2
    return 1
  fi

  echo "[$order] HIR ownership ok: make_u32=$make_u32_id make_u64=$make_u64_id"
}

overall_status=0

for source in \
  "$ROOT_DIR/regression_tests/generic_untyped_record_return_repro.cr" \
  "$ROOT_DIR/regression_tests/generic_untyped_record_return_reverse_repro.cr"
do
  order="forward"
  [[ "$source" == *reverse* ]] && order="reverse"
  stem="generic_$order"
  hir_out="$WORKDIR/$stem"
  hir_log="$WORKDIR/$stem.hir.log"
  compile_log="$WORKDIR/$stem.compile.log"
  run_log="$WORKDIR/$stem.run.log"

  if [[ "$CHECK_HIR" == "1" ]]; then
    CRYSTAL_CACHE_DIR="$WORKDIR/cache-$stem" \
      "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
      "$source" --no-prelude --emit hir --no-link -o "$hir_out" \
      >"$hir_log" 2>&1
    check_hir "$hir_out.hir" "$order"
  else
    echo "[$order] HIR ownership check skipped (GENERIC_RETURN_CHECK_HIR=0)"
  fi

  set +e
  CRYSTAL_CACHE_DIR="$WORKDIR/cache-$stem-runtime" \
    "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
    "$source" --no-prelude -o "$WORKDIR/$stem.bin" \
    >"$compile_log" 2>&1
  compile_status=$?
  set -e
  if [[ "$compile_status" -ne 0 ]]; then
    echo "[$order] inconclusive: compiler failed before runtime (exit=$compile_status)" >&2
    tail -n 40 "$compile_log" >&2 || true
    overall_status=2
    continue
  fi

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$WORKDIR/$stem.bin" 5 512 >"$run_log" 2>&1
  runtime_status=$?
  set -e
  if [[ "$runtime_status" -ne 0 ]]; then
    echo "[$order] reproduced: compiled program failed its semantic check (exit=$runtime_status)" >&2
    tail -n 40 "$run_log" >&2 || true
    [[ "$overall_status" -lt 2 ]] && overall_status=1
    continue
  fi
  echo "[$order] runtime ok"
done

if [[ "$overall_status" -ne 0 ]]; then
  exit "$overall_status"
fi

echo "PASS: exact untyped generic factory return ownership survives both discovery orders"
