#!/usr/bin/env bash
# Check that a NoReturn child path leaves the parent tail value available, while
# a same-named method from another source unit still keeps its own Nil result.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"

[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -n "$ORIGINAL" && -x "$ORIGINAL" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "candidate, original Crystal, SAFE runner, or installed Crystal stdlib is unavailable" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/process-spawn-result-flow.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/exit_support.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

# Match the standard integer case-comparison contract in this no-prelude
# fixture; otherwise `case Int32` cannot resolve `===`.
struct Int32
  def ===(other : Int32) : Bool
    self == other
  end
end

# Empty-prelude codegen needs exception hooks for the ensure-shaped control.
# The tested parent path never raises; an unexpected raise must fail the run.
fun __crystal_personality(version : Int32, actions : Int32, cls : UInt64, ex : Void*, ctx : Void*) : Int32
  0
end

fun __crystal_get_exception(ex : Void*) : UInt64
  0_u64
end

fun __crystal_raise(ex : Void*) : NoReturn
  LibC._exit(99)
end
CRYSTAL

# This mirrors spawn's relevant shape: a nullable fork result selects a child
# branch that cannot return, followed by the parent's pid as the method tail.
cat >"$WORK_DIR/tail_owner.cr" <<'CRYSTAL'
module TailOwner
  class Factory
    def self.spawn_like(pid : Int32?)
      if !pid
        LibC._exit(91)
      end
      pid
    end
  end
end
CRYSTAL

cat >"$WORK_DIR/ensure_owner.cr" <<'CRYSTAL'
module EnsureOwner
  class Factory
    def self.spawn_like(pid : Int32?)
      if !pid
        begin
          LibC.putchar(88)
        ensure
          LibC._exit(92)
        end
      end
      pid
    end
  end
end
CRYSTAL

# These declarations deliberately live in separate required source units and
# use the same method spelling, so the negative checks selected source identity.
cat >"$WORK_DIR/int_owner.cr" <<'CRYSTAL'
module IntOwner
  class Factory
    def self.spawn_like(value : Int32)
      value
    end
  end
end
CRYSTAL

cat >"$WORK_DIR/nil_owner.cr" <<'CRYSTAL'
module NilOwner
  class Factory
    def self.spawn_like(value : Int32)
      nil
    end
  end
end
CRYSTAL

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
require "./exit_support"
require "./tail_owner"
require "./ensure_owner"
require "./int_owner"
require "./nil_owner"

class IntSink
  def self.consume(value : Int32)
    LibC.putchar(value)
  end
end

IntSink.consume(TailOwner::Factory.spawn_like(65))
IntSink.consume(EnsureOwner::Factory.spawn_like(66))
IntSink.consume(IntOwner::Factory.spawn_like(67))
LibC.putchar(10)
CRYSTAL
printf 'ABC\n' >"$WORK_DIR/positive.expected"

# Exercise the inferred return of fork_for_exec's essential case shape without
# creating a real process. The nullable consumer observes both the nil child
# arm and the integer parent arm; only the -1 arm is non-returning.
cat >"$WORK_DIR/case_return_positive.cr" <<'CRYSTAL'
require "./exit_support"

module ForkResultOracle
  def self.fork_result(pid : Int32)
    case pid
    when 0
      nil
    when -1
      LibC._exit(93)
    else
      pid
    end
  end
end

class NullablePidSink
  def self.observe(pid : Int32?)
    if pid
      LibC.putchar(pid)
    else
      LibC.putchar(78)
    end
  end
end

NullablePidSink.observe(ForkResultOracle.fork_result(65))
NullablePidSink.observe(ForkResultOracle.fork_result(0))
LibC.putchar(10)
CRYSTAL
printf 'AN\n' >"$WORK_DIR/case_return_positive.expected"

# Feed the inferred nullable case result through the same child test and
# rescue/ensure shape as spawn. The child branch is statically non-returning;
# the parent tail must retain the PID and narrow to Int32 for the sink.
cat >"$WORK_DIR/rescue_ensure_positive.cr" <<'CRYSTAL'
require "./exit_support"

module ForkResultOracle
  def self.fork_result(pid : Int32)
    case pid
    when 0
      nil
    when -1
      LibC._exit(93)
    else
      pid
    end
  end
end

module SpawnFlowOracle
  def self.spawn_like(pid : Int32?)
    if !pid
      begin
        LibC.putchar(88)
      rescue ex
        LibC.putchar(89)
      ensure
        LibC._exit(92)
      end
    end
    pid
  end
end

class IntPidSink
  def self.consume(pid : Int32)
    LibC.putchar(pid)
  end
end

IntPidSink.consume(SpawnFlowOracle.spawn_like(ForkResultOracle.fork_result(66)))
LibC.putchar(10)
CRYSTAL
printf 'B\n' >"$WORK_DIR/rescue_ensure_positive.expected"

# Preserve the Process.spawn shape across two nested yielding helpers: a
# case-valued child result is packed with errno, returned through a tuple-valued
# call, destructured, then narrowed before the integer consumer. No fork occurs.
cat >"$WORK_DIR/nested_yield_tuple_multiassign_positive.cr" <<'CRYSTAL'
require "./exit_support"

module NestedForkTupleOracle
  def self.result_for(child_pid : Int32)
    case child_pid
    when 0
      nil
    when -1
      LibC._exit(94)
    else
      child_pid
    end
  end

  def self.make_tuple(child_pid : Int32, child_errno : Int32)
    {result_for(child_pid), child_errno}
  end

  def self.inner_yield(child_pid : Int32, child_errno : Int32)
    yield make_tuple(child_pid, child_errno)
  end

  def self.outer_yield(child_pid : Int32, child_errno : Int32)
    yield inner_yield(child_pid, child_errno) { |inner_tuple| inner_tuple }
  end
end

class NullablePidSink
  def self.observe(pid : Int32?)
    case pid
    when nil
      LibC.putchar(78)
    else
      LibC.putchar(pid)
    end
  end
end

pid, errno = NestedForkTupleOracle.outer_yield(67, 69) { |outer_tuple| outer_tuple }
NullablePidSink.observe(pid)
LibC.putchar(errno)

pid, errno = NestedForkTupleOracle.outer_yield(0, 70) { |outer_tuple| outer_tuple }
NullablePidSink.observe(pid)
LibC.putchar(errno)
LibC.putchar(10)
CRYSTAL
printf 'CENF\n' >"$WORK_DIR/nested_yield_tuple_multiassign_positive.expected"

cat >"$WORK_DIR/reject_nil_to_int.cr" <<'CRYSTAL'
require "./exit_support"
require "./tail_owner"
require "./ensure_owner"
require "./int_owner"
require "./nil_owner"

class IntSink
  def self.consume(value : Int32)
    LibC.putchar(value)
  end
end

IntSink.consume(NilOwner::Factory.spawn_like(65))
CRYSTAL

ORIGINAL_LINK_ARGS=()
ADAMAS_LINK_ENV=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
  ADAMAS_LINK_ENV=(ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
fi

compile_case() {
  local stage="$1" name="$2" status=0 source="$WORK_DIR/$2.cr"
  local output="$WORK_DIR/$stage.$name.bin"
  local log="$WORK_DIR/$stage.$name.compile.log"
  local cache="$WORK_DIR/cache.$stage.$name"
  if [[ "$stage" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.$name.compile.resources" \
      "$SAFE_RUNNER" "$ORIGINAL" 180 8192 build --prelude=empty --no-debug \
      "${ORIGINAL_LINK_ARGS[@]}" "$source" -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 "${ADAMAS_LINK_ENV[@]}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.$name.compile.resources" \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$source" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  return "$status"
}

run_positive() {
  local stage="$1" name="${2:-positive}" output="$WORK_DIR/$stage.$name.bin"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.$name.run.resources" \
    "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$stage.$name.stdout" \
    2>"$WORK_DIR/$stage.$name.run.log"; then
    echo "FAIL[$stage/$name]: runtime failed" >&2
    cat "$WORK_DIR/$stage.$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$stage.$name.run.log" || {
    cat "$WORK_DIR/$stage.$name.run.log" >&2
    return 1
  }
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$stage.$name.stdout"
}

reject_nil_to_int() {
  local stage="$1" status=0
  if compile_case "$stage" reject_nil_to_int; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -ne 1 || -e "$WORK_DIR/$stage.reject_nil_to_int.bin" ]]; then
    echo "FAIL[$stage/reject_nil_to_int]: expected a semantic Nil-to-Int32 rejection" >&2
    cat "$WORK_DIR/$stage.reject_nil_to_int.compile.log" >&2
    return 1
  fi
  python3 - "$WORK_DIR/$stage.reject_nil_to_int.compile.log" <<'PY_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace").lower()
assert "nil" in text and "consume" in text, text
assert "no overload matches" in text or ("int32" in text and "expect" in text), text
for forbidden in ("syntax error", "parser errors", "internal compiler error", "bug:"):
    assert forbidden not in text, text
assert "error" in text, text
PY_REJECT
}

# Original Crystal qualifies every positive and the strict Nil-to-Int32 control
# before the candidate is evaluated.
for stage in original adamas; do
  for name in positive case_return_positive rescue_ensure_positive nested_yield_tuple_multiassign_positive; do
    if ! compile_case "$stage" "$name"; then
      echo "FAIL[$stage/$name]: compile failed" >&2
      cat "$WORK_DIR/$stage.$name.compile.log" >&2
      exit 1
    fi
    run_positive "$stage" "$name"
  done
  reject_nil_to_int "$stage"
  echo "PASS[$stage]: case, nested-yield tuple, rescue/ensure NoReturn tail flow, source owners, and Nil rejection"
done
