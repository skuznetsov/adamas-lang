#!/usr/bin/env bash
# A nested type named like a primitive (`Outer::WUInt::UInt128`) must shadow
# the top-level primitive inside its namespace (return types, `.new`, `self`).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested_primitive_name_shadow_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
check() {
  local case_name="$1" expected="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" --no-prelude -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDOUT ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/c1.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
struct UInt128
  def self.new(value)
    LibC.printf("WRONG\n")
    value
  end
end


module Outer
  module WUInt
    struct UInt128
      getter high : UInt64
      getter low : UInt64
      def initialize(@high : UInt64, @low : UInt64)
      end
      def unsafe_add!(n : UInt64) : self
        sum = @low &+ n
        @high &+= (sum < @low ? 1 : 0)
        @low = sum
        self
      end
    end

    def self.umul128(x : UInt64, y : UInt64) : UInt128
      UInt128.new(high: x &* 2, low: y)
    end

    def self.umul192_upper128(x : UInt64, y : UInt128) : UInt128
      r = umul128(x, y.high)
      r.unsafe_add!(y.low)
      r
    end
  end
end

v = Outer::WUInt.umul192_upper128(3_u64, Outer::WUInt::UInt128.new(high: 5_u64, low: 7_u64))
LibC.printf("%llu %llu\n", v.high, v.low)
CR
check c1 '6 12'

if [ "$status" -ne 0 ]; then
  echo "FAIL: nested UInt128 did not shadow the primitive" >&2
  exit 1
fi
echo "PASS: nested primitive-named type shadows the primitive"
