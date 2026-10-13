#!/usr/bin/env bash
# Regression: llvm_backend carried legacy raw-IR overrides for
# `Thread::Mutex.new` / `#initialize` (fixed 72-byte malloc, hardcoded
# type_id, pthread_mutex_init AT %self). The generic layout places @mutex at
# offset 8 and `to_unsafe` = pointerof(@mutex), so the lock call saw an
# uninitialized mutex -> EINVAL -> RuntimeError.from_os_error abort in every
# full-prelude program reaching Thread::Mutex#lock (Crystal.init_runtime).
# The generic `out @ivar` / `pointerof(@ivar)` lowering is correct by itself.
# Expected: exit 0 (sig set, lock/unlock ok, neighbour ivars intact).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/thread_mutex_inline_ivar_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/tm.cr" <<'CR'
lib LibC
  struct PthreadMutexT
    sig : Int64
    opaque : UInt8[56]
  end

  struct PthreadMutexattrT
    sig : Int64
    opaque : UInt8[8]
  end

  fun pthread_mutexattr_init(a : PthreadMutexattrT*) : Int32
  fun pthread_mutexattr_settype(a : PthreadMutexattrT*, t : Int32) : Int32
  fun pthread_mutexattr_destroy(a : PthreadMutexattrT*) : Int32
  fun pthread_mutex_init(m : PthreadMutexT*, a : PthreadMutexattrT*) : Int32
  fun pthread_mutex_lock(m : PthreadMutexT*) : Int32
  fun pthread_mutex_unlock(m : PthreadMutexT*) : Int32
  fun exit(code : Int32) : NoReturn
end

class Thread
  class Mutex
    @before = 0x1111_i64
    @after = 0x2222_i64

    def initialize
      attributes = uninitialized LibC::PthreadMutexattrT
      LibC.pthread_mutexattr_init(pointerof(attributes))
      LibC.pthread_mutexattr_settype(pointerof(attributes), 0)
      ret = LibC.pthread_mutex_init(out @mutex, pointerof(attributes))
      LibC.exit(10) unless ret == 0
      LibC.pthread_mutexattr_destroy(pointerof(attributes))
    end

    def check : Int32
      r = 0
      r |= 1 if @mutex.sig == 0_i64
      r |= 2 unless LibC.pthread_mutex_lock(self) == 0
      r |= 4 unless LibC.pthread_mutex_unlock(self) == 0
      r |= 8 unless @before == 0x1111_i64 && @after == 0x2222_i64
      r
    end

    def to_unsafe
      pointerof(@mutex)
    end
  end
end

LibC.exit(Thread::Mutex.new.check)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 4096 \
    "$WORK_DIR/tm.cr" --no-prelude -o "$WORK_DIR/tm" >"$WORK_DIR/tm.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/tm.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/tm" 5 512 >"$WORK_DIR/tm.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/tm.run.log"; then
  echo "FAIL: Thread::Mutex inline pthread ivar broken (bits: 1=sig 2=lock 4=unlock 8=neighbours)" >&2
  tail -5 "$WORK_DIR/tm.run.log" >&2
  exit 1
fi
echo "PASS"
