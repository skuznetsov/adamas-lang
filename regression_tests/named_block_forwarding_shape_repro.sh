#!/usr/bin/env bash
# Named values must contribute to resolver arity while raw positional shape stays separate.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-block-forwarding.XXXXXX")"
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
module NamedBlockForwardingContract
  module Scheduler
    def spawn(*, name : String? = nil, &block : -> Int32) : Int32
      block.call
    end

    abstract def spawn(*, name : String? = nil, same_thread : Bool, &block : -> Int32) : Int32
  end

  module Parallel
    class Scheduler
      include NamedBlockForwardingContract::Scheduler

      def spawn(*, name : String? = nil, same_thread : Bool, &block : -> Int32) : Int32
        return 99 if same_thread
        self.spawn(name: name, &block)
      end
    end
  end
end

scheduler = NamedBlockForwardingContract::Parallel::Scheduler.new
puts scheduler.spawn(name: "outer", same_thread: false) { 41 }
puts scheduler.spawn(name: "inner", same_thread: true) { 42 }

class MixedNamedBlockScheduler
  def spawn(seed : Int32, *, name : String, same_thread : Bool, &block : -> Int32) : Int32
    return seed + 100 if same_thread
    seed + block.call
  end

end

mixed_scheduler = MixedNamedBlockScheduler.new
puts mixed_scheduler.spawn(2, name: "mixed", same_thread: false) { 40 }
puts mixed_scheduler.spawn(2, name: "branch", same_thread: true) { 41 }

module NamedVirtualShape
  module Scheduler
    abstract def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
  end

  class ParallelScheduler
    include Scheduler

    def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
      return 99 if same_thread
      block.call
    end
  end
end

def dispatch(scheduler : NamedVirtualShape::Scheduler, name : String, same_thread : Bool, &block : -> Int32) : Int32
  scheduler.spawn(name: name, same_thread: same_thread, &block)
end

puts dispatch(NamedVirtualShape::ParallelScheduler.new, "outer", false) { 41 }
puts dispatch(NamedVirtualShape::ParallelScheduler.new, "inner", true) { 42 }
CRYSTAL
printf '41\n99\n42\n102\n41\n99\n' >"$WORK_DIR/expected"

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original.build.resources" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/probe.cr" \
  -o "$WORK_DIR/original.bin" --link-flags=-fuse-ld=/usr/bin/ld \
  >"$WORK_DIR/original.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/original.build.log" >&2; exit 1; }
status=0
RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original.run.resources" \
  "$SAFE_RUNNER" "$WORK_DIR/original.bin" 10 512 \
  >"$WORK_DIR/original.stdout" 2>"$WORK_DIR/original.run.log" || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/original.run.log" >&2; exit 1; }
diff -u "$WORK_DIR/expected" "$WORK_DIR/original.stdout"

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" \
  ADAMAS_LLVM_CACHE=0 \
  ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate.build.resources" \
  "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" \
  --no-prelude --no-ast-cache --no-llvm-cache -o "$WORK_DIR/candidate.bin" \
  >"$WORK_DIR/candidate.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/candidate.build.log" >&2; exit 1; }
status=0
RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate.run.resources" \
  "$SAFE_RUNNER" "$WORK_DIR/candidate.bin" 10 512 \
  >"$WORK_DIR/candidate.stdout" 2>"$WORK_DIR/candidate.run.log" || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/candidate.run.log" >&2; exit 1; }
diff -u "$WORK_DIR/expected" "$WORK_DIR/candidate.stdout"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"

printf 'PASS: named-block forwarding preserves positional, named, and block call shape\n'
