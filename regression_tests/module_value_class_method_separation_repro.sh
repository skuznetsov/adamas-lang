#!/usr/bin/env bash
# Module-typed values retain instance dispatch when a class method has the same name.
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
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-value-dispatch.XXXXXX")"
cleanup() {
  if [[ "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/class_first.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end
module DualOwner
  def self.pick(limit)
    65
  end
  def pick(limit : Int) : Int32
    66
  end
end
class FirstOwner
  include DualOwner
end
class SecondOwner
  include DualOwner
  def pick(limit : Int) : Int32
    67
  end
end
def read_module(owner : DualOwner? = nil) : Int32
  receiver = owner || FirstOwner.new
  receiver.pick(2)
end
LibC.putchar(DualOwner.pick(2))
LibC.putchar(read_module)
LibC.putchar(read_module(FirstOwner.new))
LibC.putchar(read_module(SecondOwner.new))
LibC.putchar(10)
CRYSTAL
printf 'ABBC\n' >"$WORK_DIR/class_first.expected"

cat >"$WORK_DIR/value_first.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end
module DualOwner
  def self.pick(limit)
    65
  end
  def pick(limit : Int) : Int32
    66
  end
end
class FirstOwner
  include DualOwner
end
class SecondOwner
  include DualOwner
  def pick(limit : Int) : Int32
    67
  end
end
def read_module(owner : DualOwner? = nil) : Int32
  receiver = owner || FirstOwner.new
  receiver.pick(2)
end
LibC.putchar(read_module)
LibC.putchar(read_module(FirstOwner.new))
LibC.putchar(read_module(SecondOwner.new))
LibC.putchar(DualOwner.pick(2))
LibC.putchar(10)
CRYSTAL
printf 'BBCA\n' >"$WORK_DIR/value_first.expected"

cat >"$WORK_DIR/type_literals.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end
module SharedPick
  def pick(value : Int32) : Int32
    value
  end
end
module ExtendedOwner
  extend SharedPick
end
module SelfOwner
  extend self
  def pick(value : Int32) : Int32
    value
  end
end
module GenericOwner(T)
  def self.pick(value : T) : T
    value
  end
end
LibC.putchar(ExtendedOwner.pick(65))
LibC.putchar(SelfOwner.pick(66))
LibC.putchar(GenericOwner(Int32).pick(67))
local_owner = SelfOwner
LibC.putchar(local_owner.pick(68))
LibC.putchar(10)
CRYSTAL
printf 'ABCD\n' >"$WORK_DIR/type_literals.expected"

compile_and_check() {
  local producer="$1" fixture="$2"
  local bin="$WORK_DIR/$producer.$fixture.bin"
  local cache="$WORK_DIR/$producer.$fixture.cache"
  local build_log="$WORK_DIR/$producer.$fixture.build.log"
  local run_log="$WORK_DIR/$producer.$fixture.run.log"
  local stdout="$WORK_DIR/$producer.$fixture.stdout"
  local status=0
  mkdir -p "$cache"
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$fixture.build.resources" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/$fixture.cr" \
      -o "$bin" --no-debug --link-flags=-fuse-ld=/usr/bin/ld >"$build_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$fixture.build.resources" \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/$fixture.cr" \
      --no-debug --no-ast-cache --no-llvm-cache -o "$bin" >"$build_log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$build_log" >&2
    return "$status"
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$fixture.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$stdout" 2>"$run_log" || status=$?
  if [[ "$status" != 0 ]] || ! rg -Fq '[EXIT: 0]' "$run_log"; then
    cat "$run_log" >&2
    return 1
  fi
  diff -u "$WORK_DIR/$fixture.expected" "$stdout"
}

for fixture in class_first value_first type_literals; do
  compile_and_check original "$fixture"
  compile_and_check candidate "$fixture"
  diff -u "$WORK_DIR/original.$fixture.stdout" "$WORK_DIR/candidate.$fixture.stdout"
done
printf 'PASS: module value dispatch and type-literal class methods match Crystal in both call orders\n'
