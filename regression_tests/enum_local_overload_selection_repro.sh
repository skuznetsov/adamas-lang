#!/usr/bin/env bash
# A local bound to an enum value inside a def must keep its enum type for
# overload selection. Enum values travel in their base-integer carrier, and the
# assignment recorded that carrier as the local's flow type, so 1.22.1's
# `errno = Errno.new(ret); RuntimeError.from_os_error("...", errno)` failed with
# "no overload matches ... (String, Int32)" against `Errno | WinError | Nil`.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum-local-overload.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

enum Errno : Int32
  NONE  = 0
  EPERM = 1
end

enum WinError : UInt32
  ERROR_SUCCESS = 0
end

module ErrorClassMethods
  def from_os_error(message : String?, os_error : Errno | WinError | Nil, **opts) : Int32
    41
  end
end

class RErr
  extend ErrorClassMethods
end

def with_block(&)
  yield
end

struct Proc(*T, R)
  @[Primitive(:proc_call)]
  @[Raises]
  def call(*args : *T) : R
  end
end

# Captured block: like GC.syscall, the block becomes a heap Proc and the
# written locals move into boxes.
def syscall(&proc : ->) : Nil
  proc.call
end
CR

write_case() {
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$2"; } > "$WORK_DIR/$1.cr"
}

write_case def_local_new '
def run(ret : Int32) : Int32
  errno = Errno.new(ret)
  RErr.from_os_error("m", errno) + 1
end

LibC.exit(run(1))'

write_case def_local_member '
def run : Int32
  errno = Errno::EPERM
  RErr.from_os_error("m", errno) + 1
end

LibC.exit(run)'

write_case reassigned_local '
def run(ret : Int32) : Int32
  errno = Errno::NONE
  errno = Errno.new(ret)
  RErr.from_os_error("m", errno) + 1
end

LibC.exit(run(1))'

write_case multi_assign '
def run : Int32
  ret, errno = 1, Errno::NONE
  RErr.from_os_error("m", errno) + ret
end

LibC.exit(run)'

write_case block_written_local '
def run : Int32
  ret, errno = 0, Errno::NONE
  with_block do
    ret = 1
    errno = Errno.new(1)
  end
  return 0 if ret == 0
  RErr.from_os_error("nanosleep", errno) + 1
end

LibC.exit(run)'

write_case yielded_block_param '
def each_err(&)
  yield Errno.new(1)
end

def run : Int32
  r = 0
  each_err do |e|
    r = RErr.from_os_error("blk", e) + 1
  end
  r
end

LibC.exit(run)'

write_case captured_reassigned_local '
def run(ret : Int32) : Int32
  errno = Errno.new(ret)
  r = 0
  with_block do
    r = RErr.from_os_error("cap", errno) + 1
  end
  errno = Errno.new(0)
  r
end

LibC.exit(run(1))'

# Thread.sleep shape: the locals live in heap boxes written by the captured
# block; reading the box after the block must still see Errno.
write_case captured_proc_written_local '
def run : Int32
  ret, errno = 0, Errno::NONE
  syscall do
    ret = 1
    errno = Errno.new(1)
  end
  return 0 if ret == 0
  if ret == 1
    return RErr.from_os_error("nanosleep", errno) + 1
  end
  7
end

LibC.exit(run)'

# A captured box is an enum only while every write stores that enum: after an
# Int32 written inside the block or by the parent, a parent read is Int32.
write_case captured_int_block_write '
def pick(x : Int32) : Int32
  7
end

def pick(x : Errno) : Int32
  20
end

def run : Int32
  v = Errno::EPERM
  syscall do
    v = 3
  end
  pick(v)
end

LibC.exit(run)'

write_case captured_int_parent_write '
def pick(x : Int32) : Int32
  7
end

def pick(x : Errno) : Int32
  20
end

def run : Int32
  v = Errno::EPERM
  r = 0
  syscall do
    r = 1
    w = v
  end
  v = 3
  pick(v)
end

LibC.exit(run)'

# A closure may run after any later write, so reads inside it stay on the
# carrier; the parent reassignment must not leak an enum identity into it.
# (Known gap: an enum read inside a closure still infers as its Int32 carrier.)
write_case closure_after_parent_reassign '
def pick(x : Int32) : Int32
  7
end

def pick(x : Errno) : Int32
  20
end

def run : Int32
  v = Errno::EPERM
  pr = ->{ pick(v) }
  v = 3
  pr.call
end

LibC.exit(run)'

# The carrier must not leak the other way: a plain Int32 local still selects
# the Int32 overload while the enum local selects the Errno one.
write_case int_and_enum_overloads '
def pick(x : Int32) : Int32
  40
end

def pick(x : Errno) : Int32
  2
end

def run(ret : Int32) : Int32
  plain = ret
  errno = Errno.new(ret)
  pick(plain) + pick(errno)
end

LibC.exit(run(1))'

# An enum-returning class method infers as its enum even after its body is
# lowered: the lowered return type is the Int32 carrier, and the block write
# below is typed from the method's return before the block is lowered.
write_case lowered_enum_class_method '
enum Errno
  def self.make : self
    Errno.new(1)
  end
end

def pick(x : Int32) : Int32
  7
end

def pick(x : Errno) : Int32
  42
end

def run : Int32
  e = Errno::NONE
  r = 0
  syscall do
    r = 1
    e = Errno.make
  end
  pick(e)
end

pre = Errno.make
LibC.exit(run)'

CASES=(def_local_new:42 def_local_member:42 reassigned_local:42 multi_assign:42 block_written_local:42 yielded_block_param:42 captured_reassigned_local:42 captured_proc_written_local:42 captured_int_block_write:7 captured_int_parent_write:7 closure_after_parent_reassign:7 int_and_enum_overloads:42 lowered_enum_class_method:42)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
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
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d enum local overload case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'enum local overload cases passed\n'
