#!/usr/bin/env bash
# Missing constructor arguments must execute defaults and retain field layout.
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
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zero-constructor-defaults.XXXXXX")"
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
  fun exit(status : Int32) : NoReturn
  fun putchar(value : Int32) : Int32
end
struct DefaultSpan
  getter value : Int32
  def initialize(@value : Int32)
  end
end
class DefaultOwner
  DEFAULT = 41.to_default_span
  getter every
  getter other
  def initialize(@every = DEFAULT)
    @other = 42.to_default_span
  end
end
struct Int32
  def to_default_span : DefaultSpan
    DefaultSpan.new(self)
  end
end
class InheritedOwner < DefaultOwner
end
class EffectOwner
  getter value
  def initialize(@value : Int32 = C.putchar(88))
  end
end
class DependentOwner
  getter right
  def initialize(left : Int32 = 41, @right : Int32 = left + 1)
  end
end
class ExplicitOwner
  getter value
  def initialize(@value : Int32 = 42)
  end
  def self.new
    C.putchar(89)
    77
  end
end
owner = DefaultOwner.new
C.exit(1) unless owner.every.value == 41
C.exit(2) unless owner.other.value == 42
explicit = DefaultOwner.new(DefaultSpan.new(43))
C.exit(3) unless explicit.every.value == 43
C.exit(4) unless explicit.other.value == 42
C.exit(5) unless InheritedOwner.new.every.value == 41
C.exit(6) unless EffectOwner.new.value == 88
C.exit(7) unless EffectOwner.new.value == 88
C.exit(8) unless EffectOwner.new(42).value == 42
C.exit(9) unless DependentOwner.new.right == 42
C.exit(10) unless ExplicitOwner.new == 77
CRYSTAL

for producer in original candidate; do
  bin="$WORK_DIR/$producer.bin"
  cache="$WORK_DIR/$producer.cache"
  mkdir -p "$cache"
  status=0
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/probe.cr" \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$WORK_DIR/$producer.build.log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache -o "$bin" >"$WORK_DIR/$producer.build.log" 2>&1 || status=$?
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
  [[ "$(cat "$WORK_DIR/$producer.out")" == XXY ]] || {
    cat "$WORK_DIR/$producer.out" >&2
    exit 1
  }
done
cmp "$WORK_DIR/original.out" "$WORK_DIR/candidate.out"
echo 'PASS: zero-argument defaults, layout, inheritance and explicit new match Crystal'
