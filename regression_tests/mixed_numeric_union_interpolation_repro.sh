#!/usr/bin/env bash
# Regression: string interpolation of a union value must convert each variant
# by its own payload type. The backend picked one conversion from the union's
# token set: a UInt64 payload was loaded as i32, and when the union also held a
# reference type every non-Int32 variant was treated as a String pointer
# (segfault in __adamas_string_interpolate; S3 prelude hello crashed this way).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mixed_numeric_union_interpolation_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/m2.cr" <<'CR'
lib LibC
  fun puts(s : UInt8*) : Int32
  fun exit(code : Int32) : NoReturn
end
def pick(f : Int32) : UInt64 | Int32
  if f > 0
    5_000_000_000_u64
  else
    7
  end
end
def pick3(f : Int32) : UInt64 | Int32 | String
  if f > 1
    "s"
  elsif f > 0
    24_u64
  else
    -3
  end
end
def pickc(f : Int32) : Int16 | Int64 | Char
  if f > 1
    -5_i16
  elsif f > 0
    -9_000_000_000_i64
  else
    'z'
  end
end
LibC.puts("a=#{pick(1)} b=#{pick(0)}".to_unsafe)
LibC.puts("c=#{pick3(2)} d=#{pick3(1)} e=#{pick3(0)}".to_unsafe)
LibC.puts("f=#{pickc(2)} g=#{pickc(1)} h=#{pickc(0)}".to_unsafe)
LibC.exit(0)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/m2.cr" --no-prelude -o "$WORK_DIR/m2" >"$WORK_DIR/m2.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/m2.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/m2" 5 512 >"$WORK_DIR/m2.run.log" 2>&1 || true
expected=$'a=5000000000 b=7\nc=s d=24 e=-3\nf=-5 g=-9000000000 h=z'
actual="$(grep -E '^[a-h]=' "$WORK_DIR/m2.run.log" || true)"
if [ "$actual" != "$expected" ] || ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/m2.run.log"; then
  echo "FAIL: mixed numeric union interpolation printed wrong values" >&2
  cat "$WORK_DIR/m2.run.log" >&2
  exit 1
fi
echo "PASS: union interpolation converts each variant by its payload type"
