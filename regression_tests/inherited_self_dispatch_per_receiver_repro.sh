#!/usr/bin/env bash
# Regression: Crystal instantiates an inherited instance method per receiver
# type. V2 shares one ancestor-owned body, which is exact only while every self
# dispatch in it resolves the same way for the receiver.
#
# `IO#tell` calls `pos`; the receiver chain redeclares `pos` below `IO`
# (`FD#pos : Int64`). The shared body typed that self call by `IO#pos`, so
# `FD.new.tell` returned NoReturn or Int32 instead of Int64. In prelude hello
# this surfaced as "no overload matches
# 'Crystal::DWARF::LineNumbers::Sequence#offset=' with types Int32".
# The guard cases keep lexical constant lookup in the declaring owner and keep
# sibling receivers that do not redeclare the callee on the shared body.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inherited_self_dispatch_per_receiver.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > redeclared_self_call_feeds_setter.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class IO
  def pos
    LibC.exit(99)
  end

  def tell
    pos
  end
end

class FD < IO
  def pos : Int64
    9_i64
  end
end

class Seq
  @offset = 0_i64

  def offset=(@offset : Int64)
  end

  def offset
    @offset
  end
end

pos = FD.new.tell
s = Seq.new
s.offset = pos
LibC.exit(s.offset.to_i32!)
CR

cat > redeclared_self_call_noreturn_base.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class IO
  def posx
    LibC.exit(99)
  end

  def tell
    posx
  end
end

class FD < IO
  def posx : Int64
    9_i64
  end
end
posx = FD.new.tell
LibC.exit(posx.to_i32!)
CR

cat > lexical_constant_in_receiver_instance.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class A
  X = 1

  def k
    7
  end

  def foo
    v = k
    X
  end
end

class B < A
  X = 100_i64

  def k : Int64
    9_i64
  end
end

LibC.exit(B.new.foo)
CR

cat > lexical_constant_guard_second_shape.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Fd
  def initialize(@n : Int32, @write_timeout : Int32?)
  end

  def n
    @n
  end
end

abstract class Pl
  def wait_writable(fd : Fd) : Nil
    wait_writable(fd, fd.@write_timeout) do
      LibC.exit(3)
    end
  end

  def go(fd : Fd) : Nil
    wait_writable(fd)
  end

  def write(fd : Fd, timeout : Int32?) : Int32
    i = 0
    loop do
      i = i &+ 1
      if i < 3
        wait_writable(fd, timeout)
      else
        return fd.n
      end
    end
  end

  private def wait_writable(io, timeout = nil) : Nil
    wait_writable(io, timeout) do
      LibC.exit(4)
    end
  end

  private def wait_writable(io, timeout = nil, &) : Nil
    yield if wait(io, timeout) do |pd|
               pd > 0
             end
  end

  private def wait(io, timeout, &) : Bool
    yield io.n
    io.n > 100
  end
end

class Kq < Pl
end

def loop(&)
  while true
    yield
  end
end

k = Kq.new
f = Fd.new(28, nil)
k.go(f)
t = f.n > 0 ? nil : 5
LibC.exit(k.write(f, t))
CR

cat > sibling_receivers_share_or_split.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class A
  def foo
    bar
  end

  def bar
    1
  end
end

class B < A
  def bar
    7_i64
  end
end

class C < A
end

x = B.new.foo
y = C.new.foo
LibC.exit((x &+ 2_i64).to_i32! &+ y)
CR

exit_code() {
  local out
  out="$("$safe" "$1" 5 256 2>&1 || true)"
  printf '%s\n' "$out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1
}

fail=0
check() {
  local case_name="$1" want="$2" got_original got_candidate
  "$safe" "$original" 120 4096 build "$case_name.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$case_name.original" > "$case_name.original.log" 2>&1 ||
    { cat "$case_name.original.log" >&2; echo "ORACLE_BUILD_FAIL $case_name"; fail=1; return; }
  got_original="$(exit_code "$work/$case_name.original")"
  if [[ "$got_original" != "$want" ]]; then
    echo "ORACLE_MISMATCH $case_name: original=$got_original expected=$want"; fail=1; return
  fi
  if ! "$safe" "$candidate" 120 4096 "$case_name.cr" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$case_name.candidate" > "$case_name.candidate.log" 2>&1; then
    echo "FAIL $case_name: candidate compile failed"
    grep -a -m3 -i error "$case_name.candidate.log" || true
    fail=1; return
  fi
  got_candidate="$(exit_code "$work/$case_name.candidate")"
  if [[ "$got_candidate" != "$want" ]]; then
    echo "FAIL $case_name: candidate=$got_candidate expected=$want"; fail=1; return
  fi
  echo "ok $case_name"
}

check redeclared_self_call_feeds_setter 9
check redeclared_self_call_noreturn_base 9
check lexical_constant_in_receiver_instance 1
check lexical_constant_guard_second_shape 28
check sibling_receivers_share_or_split 10

[[ $fail == 0 ]] || exit 1
printf 'PASS inherited_self_dispatch_per_receiver\n'
