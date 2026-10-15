#!/usr/bin/env bash
# Module-typed assignments dispatch to each concrete layout, including chains.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-setter-virtual-dispatch.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

write_probe() {
  local mode="$1"
  cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib C
  fun exit(status : Int32) : NoReturn
end
CRYSTAL
  if [[ "$mode" == direct ]]; then
    cat >>"$WORK_DIR/probe.cr" <<'CRYSTAL'
module Linkable
  property previous : Linkable?
  property next : Linkable?
end
class SmallNode
  include Linkable
end
class PaddedNode
  @padding : Int64
  def initialize(@padding : Int64)
  end
  include Linkable
end
CRYSTAL
  else
    cat >>"$WORK_DIR/probe.cr" <<'CRYSTAL'
module Linkable
  class SmallNode
    include Linkable
  end
  class PaddedNode
    @padding : Int64
    def initialize(@padding : Int64)
    end
    include Linkable
  end
end
module Linkable
  property previous : Linkable?
  property next : Linkable?
end
alias SmallNode = Linkable::SmallNode
alias PaddedNode = Linkable::PaddedNode
CRYSTAL
  fi
  cat >>"$WORK_DIR/probe.cr" <<'CRYSTAL'
class LinkHolder
  getter node : Linkable
  def initialize(@node : Linkable)
  end
end
def link(node : Linkable, previous : Linkable?)
  node.previous = previous
end
def read(node : Linkable) : Linkable?
  node.previous
end
small = SmallNode.new
padded = PaddedNode.new(42_i64)
small_holder = LinkHolder.new(small)
padded_holder = LinkHolder.new(padded)
link(small_holder.node, padded_holder.node)
C.exit(1) unless read(small_holder.node)
link(padded_holder.node, small_holder.node)
C.exit(2) unless read(padded_holder.node)
link(small_holder.node, nil)
C.exit(3) if read(small_holder.node)
C.exit(4) unless read(padded_holder.node)
link(padded_holder.node, nil)
C.exit(5) if read(padded_holder.node)
small_holder.node.next = small_holder.node.previous = padded_holder.node
C.exit(6) unless small_holder.node.next
C.exit(7) unless small_holder.node.previous
small_holder.node.next = small_holder.node.previous = nil
C.exit(8) if small_holder.node.next
C.exit(9) if small_holder.node.previous
C.exit(0)
CRYSTAL
}

compile_and_run() {
  local producer="$1"
  local compiler="$2"
  shift 2
  local bin="$WORK_DIR/$mode.$producer.bin"
  local cache_dir="$WORK_DIR/$mode.$producer.cache"
  local compile_log="$WORK_DIR/$mode.$producer.compile.log"
  local run_log="$WORK_DIR/$mode.$producer.run.log"
  local status=0

  mkdir -p "$cache_dir"
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode.$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$WORK_DIR/probe.cr" \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode.$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache -o "$bin" >"$compile_log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$compile_log" >&2
    return "$status"
  fi

  status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode.$producer.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$run_log" 2>&1 || status=$?
  if [[ "$status" != 0 ]] || ! grep -Fq '[EXIT: 0]' "$run_log"; then
    cat "$run_log" >&2
    return 1
  fi
}

for mode in direct nested_reopening; do
  write_probe "$mode"
  compile_and_run original "$ORIGINAL_CRYSTAL_BIN"
  compile_and_run candidate "$COMPILER"
done
printf 'PASS: module-typed setter dispatch and chains match Crystal\n'
