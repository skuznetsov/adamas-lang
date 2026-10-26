#!/usr/bin/env bash
# A `return` inside a caller block inlined into a yielding method such as
# `Crystal::SpinLock#sync` (`lock; begin; yield; ensure; unlock; end`) runs
# the method's ensure body at the return site. That body was re-lowered under
# the caller's owner, so the implicit-self `unlock` resolved against the
# caller class and stayed an unqualified call: every prelude program failed
# with "undefined method 'unlock'" (spin_lock.cr:31, reached from
# Arena#allocate_at?). The early-exit scope now records its lexical owner
# (class, method, namespace, type parameters, inline frame) and emits the
# ensure body under it. The positive cases also check that the ensure body
# ran exactly once per early return; an ensure body calling an undeclared
# method stays rejected. Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inline-block-return-ensure-owner.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" ensure_call="$2" receiver="$3" block_body="$4"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

# No prelude: begin/ensure needs the unwind entry points to link.
fun __crystal_personality(version : Int32, actions : Int32, cls : UInt64, ex : Void*, ctx : Void*) : Int32
  0
end

fun __crystal_get_exception(ex : Void*) : UInt64
  0_u64
end

fun __crystal_raise(ex : Void*) : NoReturn
  LibC.exit(1)
end

class Counter
  @@unlocks = 0

  def self.unlocks
    @@unlocks
  end

  def self.bump
    @@unlocks &+= 1
  end
end

struct SL
  def lock
  end

  def unlock
    Counter.bump
  end

  def sync(&)
    lock
    begin
      yield
    ensure
      $ensure_call
    end
  end
end

struct Entry
  @lock = SL.new
  @v = 39

  def v
    @v
  end
end

class Ar
  def initialize
    @e = Entry.new
  end

  def go(x)
    entry = @e
    $receiver.sync do
      $block_body
    end
    entry.v &+ x
  end
end

r = Ar.new.go(2)
LibC.exit(r &+ Counter.unlocks)
CR
}

# Shape of Arena#allocate_at?: `entry.value.@lock.sync do return ... end`.
write_case ivar_receiver_return unlock 'entry.@lock' 'return entry.v &+ x'
write_case local_receiver_return unlock 'lk = entry.@lock
    lk' 'return entry.v &+ x'
write_case conditional_return unlock 'entry.@lock' 'return entry.v &+ x if x > 0'
# Control: no early exit; the normal ensure path already resolved unlock.
write_case fallthrough_control unlock 'entry.@lock' 'x &+ 0'
# Negative: SL declares no missing method.
write_case missing_ensure_call_rejected missing 'entry.@lock' 'return entry.v &+ x'

POSITIVE=(ivar_receiver_return local_receiver_return conditional_return fallthrough_control)
NEGATIVE=(missing_ensure_call_rejected)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "0" ]]; then
    printf 'FAIL %s (accepted)\n' "$name"
    failures=$((failures + 1))
  else
    printf 'PASS %s (rejected)\n' "$name"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
