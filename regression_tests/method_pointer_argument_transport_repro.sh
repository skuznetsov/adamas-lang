#!/usr/bin/env bash
# Method pointers preserve typed inputs and capture bound receivers at creation.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/method-pointer-inputs.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
class MethodPointerTarget
  def self.zero : Int32
    42
  end
  def self.add(value : Int32) : Int32
    value + 1
  end
  def self.select(left : Int32, right : Int64) : Int64
    right
  end
  def initialize(@base : Int32)
  end
  def offset(value : Int32) : Int32
    @base + value
  end
  def callback
    ->offset(Int32)
  end
end
zero = ->MethodPointerTarget.zero
puts zero.call
add = ->::MethodPointerTarget.add(Int32)
puts add.call(6)
selection = ->MethodPointerTarget.select(Int32, Int64)
puts selection.call(3, 8_i64)
receiver = MethodPointerTarget.new(10)
bound = ->receiver.offset(Int32)
receiver = MethodPointerTarget.new(90)
puts bound.call(2)
puts MethodPointerTarget.new(20).callback.call(3)
CRYSTAL

cat >"$WORK_DIR/expected" <<'EXPECTED'
42
7
8
12
23
EXPECTED

build_and_run_original() {
  local source="$1" output="$2" stem="$3" status=0
  env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$stem.cache" \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stem.build.resources.json" \
    "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$source" \
    -o "$output" --link-flags=-fuse-ld=/usr/bin/ld \
    >"$WORK_DIR/$stem.build.log" 2>&1 || status=$?
  [[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/$stem.build.log" || {
    cat "$WORK_DIR/$stem.build.log" >&2
    return 1
  }
  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stem.run.resources.json" \
    "$SAFE_RUNNER" "$output" 10 512 \
    >"$WORK_DIR/$stem.stdout" 2>"$WORK_DIR/$stem.run.log" || status=$?
  [[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/$stem.run.log" || {
    cat "$WORK_DIR/$stem.run.log" >&2
    return 1
  }
}

build_and_run_original "$WORK_DIR/probe.cr" "$WORK_DIR/original.bin" original
diff -u "$WORK_DIR/expected" "$WORK_DIR/original.stdout"

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" \
  ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate.build.resources.json" \
  "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" --no-llvm-cache --no-ast-cache --no-prelude \
  -o "$WORK_DIR/candidate.bin" >"$WORK_DIR/candidate.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/candidate.build.log" || {
  cat "$WORK_DIR/candidate.build.log" >&2
  exit 1
}
status=0
RUN_SAFE_PASSTHROUGH_STDIO=1 \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate.run.resources.json" \
  "$SAFE_RUNNER" "$WORK_DIR/candidate.bin" 10 512 \
  >"$WORK_DIR/candidate.stdout" 2>"$WORK_DIR/candidate.run.log" || status=$?
[[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/candidate.run.log" || {
  cat "$WORK_DIR/candidate.run.log" >&2
  exit 1
}
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
printf 'PASS: typed method pointers and captured receiver identity match Crystal (isolated no-prelude candidate)\n'
