#!/usr/bin/env bash
# Regression: wrapping a Tuple value into a nilable union whose tuple variant
# has different element types (Tuple(Int32, Int64) into
# Nil | Tuple(Int32, Int64 | Nil)) matched the variant by generic base name
# and wrapped the narrow tuple as-is. The payload layout then disagreed with
# the variant type and the union element read back as 0. (S2:
# literal_for_type_param_value returned value 0, so StaticArray#size was 0
# and Float::Printer aborted in S3.)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nilable_tuple_union_wrap_widen_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/nt.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

alias LV = Int64 | Nil
alias WV = Int64 | UInt64 | Nil

def narrow_nilable : {Int32, LV}?
  iv = 17_i64
  {1, iv}
end

def narrow_wide : {Int32, WV}?
  uv = 23_u64
  {2, uv}
end

# Positive control: non-nilable target (tuple-to-tuple coercion path).
def plain : {Int32, LV}
  iv = 31_i64
  {3, iv}
end

code = 0
if r = narrow_nilable
  v = r[1]
  code |= 1 unless r[0] == 1 && v.is_a?(Int64) && v == 17
else
  code |= 1
end
if r = narrow_wide
  v = r[1]
  code |= 2 unless r[0] == 2 && v.is_a?(UInt64) && v == 23
else
  code |= 2
end
p = plain
pv = p[1]
code |= 4 unless p[0] == 3 && pv.is_a?(Int64) && pv == 31
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/nt.cr" --no-prelude -o "$WORK_DIR/nt" >"$WORK_DIR/nt.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/nt.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/nt" 5 512 >"$WORK_DIR/nt.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/nt.run.log"; then
  echo "FAIL: tuple wrapped into nilable union without element-wise widening" >&2
  cat "$WORK_DIR/nt.run.log" >&2
  exit 1
fi
echo "PASS: tuple is widened to the union's tuple variant before wrapping"
