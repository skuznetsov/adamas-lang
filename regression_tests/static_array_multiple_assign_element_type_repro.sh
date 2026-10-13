#!/usr/bin/env bash
# Multiple assignment from StaticArray must preserve the descriptor's element type.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/static_array_multiple_assign.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Probe
  def self.select(value : Int64) : Int32
    value == 0x1_0000_0007_i64 ? 1 : 0
  end

  def self.select(value : Int32) : Int32
    0
  end
end

def static_array_case : Int32
  values = uninitialized StaticArray(Int64, 2)
  values[0] = 0x1_0000_0007_i64
  values[1] = 0x2_0000_0009_i64
  first, second = values
  direct = values[0]

  result = 0
  result |= 1 unless first == 0x1_0000_0007_i64
  result |= 2 unless second == 0x2_0000_0009_i64
  result |= 4 unless direct == first
  result |= 8 unless Probe.select(first) == 1
  result
end

def tuple_guard_case : Int32
  first, second = {11_i64, 12_i64}
  result = 0
  result |= 1 unless first == 11_i64
  result |= 2 unless second == 12_i64
  result
end

LibC.exit(static_array_case | (tuple_guard_case << 4))
CR

HIR_OUT="$WORK_DIR/repro_hir"
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" --no-prelude --emit hir --no-link -o "$HIR_OUT" \
    >"$WORK_DIR/hir.build.log" 2>&1; then
  echo "static array multiple assignment: HIR compile failed" >&2
  tail -30 "$WORK_DIR/hir.build.log" >&2
  exit 1
fi

HIR="$HIR_OUT.hir"
if [[ ! -f "$HIR" ]]; then
  echo "static array multiple assignment: compiler did not emit HIR at $HIR" >&2
  tail -30 "$WORK_DIR/hir.build.log" >&2
  exit 1
fi

awk '
  /^func @static_array_case\(/ { in_function = 1 }
  in_function && /^func @/ && $0 !~ /^func @static_array_case\(/ { exit }
  in_function { print }
' "$HIR" >"$WORK_DIR/static_array_case.hir"

static_type() {
  sed -nE "s/^ *%[0-9]+ = local \"$1\" : ([0-9]+) .*/\\1/p" \
    "$WORK_DIR/static_array_case.hir" | head -1
}

first_type="$(static_type first)"
second_type="$(static_type second)"
direct_type="$(static_type direct)"
index_types="$(sed -nE 's/^ *%[0-9]+ = index_get .* : ([0-9]+)$/\1/p' \
  "$WORK_DIR/static_array_case.hir")"
index_count="$(printf '%s\n' "$index_types" | awk 'NF { n += 1 } END { print n + 0 }')"
bad_index_types="$(printf '%s\n' "$index_types" | awk -v expected="$direct_type" \
  'NF && $1 != expected { print $1 }')"

if [[ -z "$direct_type" || "$direct_type" == 0 || \
      "$first_type" != "$direct_type" || "$second_type" != "$direct_type" || \
      "$index_count" -ne 3 || -n "$bad_index_types" ]]; then
  echo "static array multiple assignment: destructured HIR lost the StaticArray element type" >&2
  printf 'first=%s second=%s direct=%s index_types=%s\n' \
    "${first_type:-missing}" "${second_type:-missing}" \
    "${direct_type:-missing}" "${index_types//$'\n'/ }" >&2
  sed -n '1,90p' "$WORK_DIR/static_array_case.hir" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" \
    >"$WORK_DIR/build.log" 2>&1; then
  echo "static array multiple assignment: compile failed" >&2
  tail -30 "$WORK_DIR/build.log" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 \
    >"$WORK_DIR/run.log" 2>&1; then
  echo "static array multiple assignment: runtime failed" >&2
  grep -E '^(STUB CALLED:|\[EXIT|\[TIMEOUT|\[KILLED)' "$WORK_DIR/run.log" >&2 ||
    cat "$WORK_DIR/run.log" >&2
  exit 1
fi

if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "static array multiple assignment: aggregate runtime check did not exit 0" >&2
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi

echo static_array_multiple_assign_element_type_repro_ok
