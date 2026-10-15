#!/usr/bin/env bash
# Abstract numeric return annotations preserve concrete result width and enforce membership.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/abstract-numeric-return.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
module AbstractNumericResult
  extend self
  def identity(value : Int) : Int
    value
  end
  def explicit(value : Int) : Int
    return value
  end
  def floating(value : Float) : Float
    value
  end
  def number : Number
    0x1_0000_002a_u64
  end
end
class AbstractClassResult
  def self.identity(value : Int) : Int
    value
  end
end
def abstract_top_result(value : Int) : Int
  value
end
module MixedNumericResults
  extend self
  def integer(flag : Bool) : Int
    if flag
      return 0x1_0000_002a_u64
    end
    42_i64
  end
  def floating(flag : Bool) : Float
    if flag
      42.5_f32
    else
      84.5_f64
    end
  end
  def number(flag : Bool) : Number
    if flag
      0x1_0000_002a_u64
    else
      42.5_f64
    end
  end
end
wide = 0x1_0000_002a_u64
C.exit(7) unless AbstractNumericResult.identity(wide) == wide
C.putchar(65)
C.exit(8) unless AbstractNumericResult.explicit(wide) == wide
C.putchar(66)
C.exit(9) unless AbstractClassResult.identity(wide) == wide
C.putchar(67)
C.exit(10) unless abstract_top_result(wide) == wide
C.putchar(68)
C.exit(11) unless AbstractNumericResult.floating(42.5_f64) == 42.5_f64
C.putchar(69)
C.exit(12) unless AbstractNumericResult.number == wide
C.putchar(70)
C.exit(13) unless MixedNumericResults.integer(true) == wide
C.exit(14) unless MixedNumericResults.integer(false) == 42_i64
C.putchar(71)
C.exit(15) unless MixedNumericResults.floating(true) == 42.5_f32
C.exit(16) unless MixedNumericResults.floating(false) == 84.5_f64
C.putchar(72)
C.exit(17) unless MixedNumericResults.number(true) == wide
C.exit(18) unless MixedNumericResults.number(false) == 42.5_f64
C.putchar(73)
CRYSTAL

for producer in original candidate; do
  bin="$WORK_DIR/$producer.bin"
  cache="$WORK_DIR/$producer.cache"
  mkdir -p "$cache"
  status=0
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/probe.cr" \
      -o "$bin" --no-debug --link-flags=-fuse-ld=/usr/bin/ld >"$WORK_DIR/$producer.build.log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache --no-debug -o "$bin" >"$WORK_DIR/$producer.build.log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$producer.build.log" >&2
    exit "$status"
  fi
  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$bin" 15 512 >"$WORK_DIR/$producer.out" 2>"$WORK_DIR/$producer.run.log" || status=$?
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$producer.run.log" >&2
    exit "$status"
  fi
  [[ "$(cat "$WORK_DIR/$producer.out")" == ABCDEFGHI ]] || {
    cat "$WORK_DIR/$producer.out" >&2
    exit 1
  }
done
cmp "$WORK_DIR/original.out" "$WORK_DIR/candidate.out"
echo 'PASS: abstract numeric return constraints retain concrete carriers'
