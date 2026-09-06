#!/usr/bin/env bash
# Numeric conversion and unsafe_as must select different same-width operations.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/numeric-conversion.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def convert(value : Int64) : Float64
  value.to_f64
end
def convert_bang(value : Int64) : Float64
  value.to_f64!
end
def convert_short(value : Int64) : Float64
  value.to_f
end
def bits(value : Int64) : Float64
  value.unsafe_as(Float64)
end
LibC.exit(11) unless convert(1_i64) == 1.0
LibC.exit(12) unless convert(-7_i64) == -7.0
LibC.exit(13) unless convert(4294967296_i64) == 4294967296.0
LibC.exit(14) unless convert_bang(2_i64) == 2.0
LibC.exit(15) unless convert_short(3_i64) == 3.0
LibC.exit(16) unless bits(4607182418800017408_i64) == 1.0
LibC.exit(17) unless 7.5.to_i64 == 7_i64
LibC.exit(18) unless (-7.5).to_i64 == -7_i64
LibC.exit(19) unless 7_i32.to_f32 == 7.0_f32
LibC.exit(20) unless 7.5_f32.to_i32 == 7_i32
LibC.exit(21) unless 9223372036854775808_u64.to_f64 == 9223372036854775808.0
LibC.exit(22) unless 1.0.unsafe_as(UInt64) == 4607182418800017408_u64
LibC.exit(0)
CRYSTAL
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$WORK_DIR/probe.cr" --no-prelude -o "$WORK_DIR/probe" \
  >"$WORK_DIR/compile.log" 2>&1 || { cat "$WORK_DIR/compile.log"; exit 1; }
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 \
  >"$WORK_DIR/run.log" 2>&1 || { cat "$WORK_DIR/run.log"; exit 1; }
echo "PASS: numeric conversions and explicit bit reinterpretation"
