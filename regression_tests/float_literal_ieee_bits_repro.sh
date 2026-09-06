#!/usr/bin/env bash
# Float literals must preserve their IEEE payload through MIR and LLVM.
#
# The decimal backend path previously emitted invalid LLVM for integral-valued
# floats (for example `fneg double 7`) and for non-exact Float32 decimals.  The
# runtime oracle below also catches a value change that still happens to parse.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/float-literal-ieee.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == 1 ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def f64_bits(value : Float64) : UInt64
  value.unsafe_as(UInt64)
end

def f32_bits(value : Float32) : UInt32
  value.unsafe_as(UInt32)
end

# Fractional, integral, negative, and signed-zero Float64 payloads.
LibC.exit(11) unless f64_bits(7.5) == 0x401e000000000000_u64
LibC.exit(12) unless f64_bits(-7.5) == 0xc01e000000000000_u64
LibC.exit(13) unless f64_bits(236.15) == 0x406d84cccccccccd_u64
LibC.exit(14) unless f64_bits(0.1) == 0x3fb999999999999a_u64
# Keep the negative integral case first so the historical `fneg ... 7`
# spelling is the first diagnostic on an unfixed compiler.
LibC.exit(15) unless f64_bits(-7.0) == 0xc01c000000000000_u64
LibC.exit(16) unless f64_bits(7.0) == 0x401c000000000000_u64
LibC.exit(17) unless f64_bits(-0.0) == 0x8000000000000000_u64

# The LLVM spelling of a Float32 constant is a rounded Float32 value promoted
# to the 64-bit APFloat representation used by LLVM IR.
LibC.exit(21) unless f32_bits(7.5_f32) == 0x40f00000_u32
LibC.exit(22) unless f32_bits(-7.5_f32) == 0xc0f00000_u32
LibC.exit(23) unless f32_bits(236.15_f32) == 0x436c2666_u32
LibC.exit(24) unless f32_bits(0.1_f32) == 0x3dcccccd_u32
LibC.exit(25) unless f32_bits(-7.0_f32) == 0xc0e00000_u32
LibC.exit(26) unless f32_bits(7.0_f32) == 0x40e00000_u32
LibC.exit(27) unless f32_bits(-0.0_f32) == 0x80000000_u32
LibC.exit(0)
CRYSTAL

COMPILE_LOG="$WORK_DIR/compile.log"
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/probe.cr" --no-prelude -o "$WORK_DIR/probe" >"$COMPILE_LOG" 2>&1; then
  echo "FAIL: compiler rejected float literal IEEE probe" >&2
  cat "$COMPILE_LOG" >&2
  exit 1
fi

LL="$WORK_DIR/probe.ll"
if [[ -s "$LL" ]]; then
  # Keep this guard focused on the old malformed form.  Valid decimal output
  # such as `7.0` remains acceptable; the runtime oracle checks its payload.
  if grep -Eq 'fneg (double|float) -?[0-9]+([[:space:]]|$)' "$LL"; then
    echo "FAIL: emitted LLVM contains an integral float without a type suffix" >&2
    grep -En 'fneg (double|float) -?[0-9]+([[:space:]]|$)' "$LL" >&2
    exit 1
  fi

  LLVM_AS="${LLVM_AS:-}"
  if [[ -z "$LLVM_AS" ]]; then
    if command -v llvm-as >/dev/null 2>&1; then
      LLVM_AS="$(command -v llvm-as)"
    elif [[ -x /opt/homebrew/opt/llvm/bin/llvm-as ]]; then
      LLVM_AS=/opt/homebrew/opt/llvm/bin/llvm-as
    fi
  fi
  if [[ -n "$LLVM_AS" && -x "$LLVM_AS" ]]; then
    if ! "$ROOT_DIR/scripts/run_safe.sh" "$LLVM_AS" 5 512 \
        "$LL" -o "$WORK_DIR/probe.bc" >"$WORK_DIR/llvm-as.log" 2>&1; then
      echo "FAIL: llvm-as rejected emitted float literal LLVM" >&2
      cat "$WORK_DIR/llvm-as.log" >&2
      exit 1
    fi
  else
    echo "NOTE: llvm-as unavailable; skipped standalone LLVM syntax check" >&2
  fi
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  echo "FAIL: float literal IEEE runtime oracle" >&2
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi

echo "PASS: float literals preserve Float64/Float32 IEEE payloads"
