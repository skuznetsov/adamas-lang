#!/usr/bin/env bash
# A block may bind fewer arguments than its expected Proc ABI.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block-proc-expected-arity.XXXXXX")"
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
lib C
  fun exit(status : Int32) : NoReturn
end

def verify(value : Int32, expected : Int32, failure : Int32)
  C.exit(failure) if value != expected
end

class OneArgumentCallbackHolder
  def initialize(&@callback : Int32 -> Nil)
  end

  def fire
    @callback.call(42)
  end
end

class TwoArgumentCallbackHolder
  def initialize(&@callback : Int32, String -> Nil)
  end

  def fire
    @callback.call(7, "tail")
  end
end

class StaleShapeAllocator
  def self.new(label : String? = nil, &block : String -> Int32)
    block.call(label || "")
  end

  def initialize(label : String, count : Int32, &@proc : Int32 -> Bool)
  end

  def ready? : Bool
    @proc.call(3)
  end
end

def require_nil(value : Nil)
end

require_nil(OneArgumentCallbackHolder.new { }.fire)
require_nil(OneArgumentCallbackHolder.new { |value| verify(value, 42, 6); 1.5 }.fire)
require_nil(OneArgumentCallbackHolder.new { |value| verify(value, 42, 7); "discarded" }.fire)
OneArgumentCallbackHolder.new { |value| verify(value, 42, 1) }.fire
TwoArgumentCallbackHolder.new { |value| verify(value, 7, 2) }.fire
TwoArgumentCallbackHolder.new { |value, suffix| verify(value, 7, 3) }.fire
C.exit(4) unless StaleShapeAllocator.new("warmup") { |label| 42 } == 42
instance = StaleShapeAllocator.new("fiber", 3) { |count| count == 3 }
C.exit(5) unless instance.ready?
C.exit(0)
CRYSTAL

compile_and_run() {
  local producer="$1"
  local compiler="$2"
  shift 2
  local bin="$WORK_DIR/$producer.bin"
  local cache_dir="$WORK_DIR/$producer.cache"
  local compile_log="$WORK_DIR/$producer.compile.log"
  local run_log="$WORK_DIR/$producer.run.log"
  local status=0

  mkdir -p "$cache_dir"
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$WORK_DIR/probe.cr" --prelude empty \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache -o "$bin" >"$compile_log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$compile_log" >&2
    return "$status"
  fi

  status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$run_log" 2>&1 || status=$?
  if [[ "$status" != 0 ]] || ! grep -Fq '[EXIT: 0]' "$run_log"; then
    cat "$run_log" >&2
    return 1
  fi
}

compile_and_run original "$ORIGINAL_CRYSTAL_BIN"
compile_and_run candidate "$COMPILER"
printf 'PASS: original and candidate preserve expected block Proc arguments\n'
