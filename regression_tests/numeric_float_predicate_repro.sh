#!/usr/bin/env bash
# HIR::TypeRef equality in lower_cast must compare type IDs, not object identity.
# The unsafe_as checks ensure ordinary numeric conversion remains distinct from
# same-width bit reinterpretation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/numeric-float-predicate.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def int_to_float(value : Int64) : Float64
  value.to_f64
end

def float32_to_float64(value : Float32) : Float64
  value.to_f64
end

def float64_to_float32(value : Float64) : Float32
  value.to_f32
end

def float_to_int(value : Float64) : Int32
  value.to_i32
end

def unsafe_int_bits(value : Int64) : Float64
  value.unsafe_as(Float64)
end

def unsafe_float_bits(value : Float64) : UInt64
  value.unsafe_as(UInt64)
end

LibC.exit(11) unless int_to_float(4294967296_i64) == 4294967296.0
LibC.exit(12) unless float32_to_float64(7.5_f32) == 7.5
LibC.exit(13) unless float64_to_float32(7.5) == 7.5_f32
LibC.exit(14) unless float_to_int(-7.5) == -7

# These are deliberately bit reinterpretations, not numeric conversions.
LibC.exit(15) unless unsafe_int_bits(4607182418800017408_i64) == 1.0
LibC.exit(16) unless unsafe_float_bits(1.0) == 4607182418800017408_u64
LibC.exit(0)
CRYSTAL

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

STAGE_BIN="$WORK_DIR/stage_bin"
STAGE_COMPILE_LOG="$WORK_DIR/stage.compile.log"
STAGE_RUN_LOG="$WORK_DIR/stage.run.log"
CRYSTAL_CACHE_DIR="$WORK_DIR/stage-cache" \
  "$RUN_SAFE" "$COMPILER" 60 4096 \
  "$WORK_DIR/probe.cr" --no-prelude -o "$STAGE_BIN" \
  >"$STAGE_COMPILE_LOG" 2>&1 || {
    cat "$STAGE_COMPILE_LOG" >&2
    exit 1
  }
"$RUN_SAFE" "$STAGE_BIN" 5 512 >"$STAGE_RUN_LOG" 2>&1 || {
  cat "$STAGE_RUN_LOG" >&2
  exit 1
}

if [[ -x "$ORIGINAL_CRYSTAL" ]]; then
  ORIGINAL_BIN="$WORK_DIR/original_bin"
  ORIGINAL_COMPILE_LOG="$WORK_DIR/original.compile.log"
  ORIGINAL_RUN_LOG="$WORK_DIR/original.run.log"
  CRYSTAL_CACHE_DIR="$WORK_DIR/original-cache" \
    "$RUN_SAFE" "$ORIGINAL_CRYSTAL" 60 8192 build "$WORK_DIR/probe.cr" \
    -o "$ORIGINAL_BIN" >"$ORIGINAL_COMPILE_LOG" 2>&1 || {
      cat "$ORIGINAL_COMPILE_LOG" >&2
      exit 1
    }
  "$RUN_SAFE" "$ORIGINAL_BIN" 5 512 >"$ORIGINAL_RUN_LOG" 2>&1 || {
    cat "$ORIGINAL_RUN_LOG" >&2
    exit 1
  }
else
  echo "NOTE: original Crystal control skipped; set ORIGINAL_CRYSTAL to its executable" >&2
fi

echo "PASS: Float32/Float64 conversions and unsafe bit reinterpretation"
