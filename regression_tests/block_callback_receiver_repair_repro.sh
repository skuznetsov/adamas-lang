#!/usr/bin/env bash
# Regression: a literal block that lower_call materializes as a callback (the
# inline-yield refusal for a callee with a return next to its yield, as in
# `yield if wait(...) do ... return ... end`) rides only as the trailing Proc of a
# `_block` target; its Call records no block region.
#
# Receiver repair took block presence only from Call#block, so for an inherited
# method re-lowered for a subclass receiver it re-keyed `Base#m$A_block` as a
# non-block call with a positional Proc. No-prelude this became a self-recursive
# `Sub#m` (SIGBUS); in prelude hello it raised "receiver repair left bodyless
# target Crystal::EventLoop::Kqueue#wait_writable$..._Proc(NoReturn)".
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-block_callback_receiver_repair.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > yield_if_do_block_return.cr <<'CR'
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
               return unless pd > 0
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

cat > yield_if_brace_block_return.cr <<'CR'
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
    yield if wait(io, timeout) { |pd| return unless pd > 0 }
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

cat > if_block_return_then_yield.cr <<'CR'
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
    if wait(io, timeout) do |pd|
         return unless pd > 0
       end
      yield
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

check yield_if_do_block_return 28
check yield_if_brace_block_return 28
check if_block_return_then_yield 28

[[ $fail == 0 ]] || exit 1
printf 'PASS block_callback_receiver_repair\n'
