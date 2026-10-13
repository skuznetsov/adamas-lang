#!/usr/bin/env bash
# Regression: numeric unary operators in macro values must produce numeric
# MacroValues so equality, arithmetic, interpolation, and nested equality see
# the NumberLiteral value and kind. Unknown/non-numeric unary nodes retain the
# opaque-node fallback rather than being coerced to numbers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_unary_numeric.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def code : Int32
  result = 0

  # Unary minus must retain the literal's numeric kind for direct and nested
  # structural equality. A different kind remains unequal.
  result |= 1 unless {{ -1 == -1_i32 }}
  result |= 2 unless {{ [-1] == [-1_i32] }}
  result |= 4 if {{ -1_i32 == -1_i64 }}

  # Unary plus is NumberLiteral#interpret("+") with no arguments: it returns
  # the original number, including its kind.
  result |= 8 unless {{ +1 == 1 }}
  result |= 16 unless {{ +1_i64 == 1_i64 }}
  result |= 32 if {{ +1_i64 == 1_i32 }}

  # Integer complement and arithmetic must consume the normalized numeric
  # value, and interpolation must still emit a correctly typed literal.
  result |= 64 unless {{ ~1 == -2 }}
  result |= 128 unless {{ ~1_i64 == -2_i64 }}
  result |= 256 unless {{ ~1_u8 == 254_u8 }}
  result |= 512 unless {{ ~1_u64 == 18446744073709551614_u64 }}
  result |= 1024 unless {{ -1 + 2 == 1 }}
  negative_i64 = {{ -1_i64 }}
  result |= 2048 unless negative_i64.is_a?(Int64) && negative_i64 == -1_i64
  complemented_u64 = {{ ~1_u64 }}
  result |= 4096 unless complemented_u64.is_a?(UInt64) && complemented_u64 == 18446744073709551614_u64

  # Float32 unary minus must round-trip through Float32's shortest decimal
  # spelling before subsequent macro equality sees the NumberLiteral value.
  result |= 8192 unless {{ -(-(+1.00000006_f32)) == 1.0000001_f32 }}
  result |= 16384 if {{ -(-(+1.00000006_f32)) == 1.00000006_f32 }}
  rounded_f32 = {{ -(-(+1.00000006_f32)) }}
  result |= 32768 unless rounded_f32.is_a?(Float32)
  result |= 65536 unless rounded_f32 == 1.0000001_f32

  # Unary interpolation must preserve signed zero as well as the Float32 kind.
  negative_zero_f32 = {{ -(0.0_f32) }}
  result |= 131072 unless {{ -(0.0_f32) == -0.0_f32 }}
  result |= 262144 unless negative_zero_f32.is_a?(Float32) && (1.0_f32 / negative_zero_f32) < 0.0_f32

  # Exercise the condition path as well as `{{ }}` value expressions.
  {% if -1 == -1_i32 %}
    result |= 524288
  {% else %}
    result |= 1048576
  {% end %}

  result
end

LibC.exit(code == 524288 ? 0 : 1)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  echo "FAIL: macro unary numeric regression did not compile"
  tail -30 "$WORK_DIR/build.log"
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "FAIL: macro unary numeric values diverged"
  cat "$WORK_DIR/run.log"
  exit 1
fi

# Adamas-specific fallback guard. These invalid unary operators are rejected by
# original Crystal's NumberLiteral interpreter, so keep them out of the valid
# semantic oracle above. Adamas should preserve opaque-node fallback without
# coercing the string operand to numeric zero or minus one.
cat >"$WORK_DIR/fallback.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def fallback_guard : Int32
  if {{ -"x" == -0 }} || {{ ~"x" == -1 }}
    1
  else
    0
  end
end

LibC.exit(fallback_guard)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
    "$WORK_DIR/fallback.cr" --no-prelude -o "$WORK_DIR/fallback" >"$WORK_DIR/fallback_build.log" 2>&1; then
  echo "FAIL: macro unary fallback guard did not compile"
  tail -30 "$WORK_DIR/fallback_build.log"
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/fallback" 5 512 >"$WORK_DIR/fallback_run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/fallback_run.log"; then
  echo "FAIL: non-numeric unary fallback was coerced"
  cat "$WORK_DIR/fallback_run.log"
  exit 1
fi

echo PASS
