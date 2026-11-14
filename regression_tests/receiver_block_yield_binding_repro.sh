#!/usr/bin/env bash
# Regression: a yield inside a block attached to a member-access receiver
# (`bsi { |v, i| yield v }.try { |i| i }`) must find the binding of its
# argument. collect_yield_arg_lists visits receivers, but the local-assignment
# walker skipped the callee's receiver, so `v` had no type, the outer block
# param fell back to its declared `B -> _` shape and the caller block was
# lowered as `Proc(Pointer, Bool)` (`no overload matches
# 'Proc(Pointer, Bool)#call' with type Int32`). Controls: the same yield
# without the chained receiver call, and an untyped `&` block parameter.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-receiver-block-yield-binding.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > chained_receiver_block.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

struct Rng(B, E)
  def initialize(@b : B, @e : E)
  end

  def bs(&block : B -> _)
    satisfied = nil
    if yield @e
      satisfied = @e
    end
    satisfied
  end
end

class Rows
  def at(i : Int32) : Int32
    i &+ 13
  end

  def bsi(&)
    Rng.new(0, 2).bs { |i| yield at(i), i }
  end

  def bsx(&)
    bsi { |v, i| yield v }.try { |i| i }
  end
end

LibC.exit(Rows.new.bsx { |r| r > 9 } || 0)
CR

cat > chained_receiver_block_cast.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

struct Rng(B, E)
  def initialize(@b : B, @e : E)
  end

  def bs(&block : B -> _)
    satisfied = nil
    if yield @e
      satisfied = @e
    end
    satisfied
  end
end

class Rows
  def at(i : Int32) : Int32
    i &+ 13
  end

  def bsi(&)
    Rng.new(0, 2).bs { |i| yield at(i), i }
  end

  def bsx(&)
    bsi { |v, i| yield v }.try { |i| i }
  end
end

LibC.exit(Rows.new.bsx { |r| r.as(Int32) > 9 } || 0)
CR

cat > control_unchained.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

struct Rng(B, E)
  def initialize(@b : B, @e : E)
  end

  def bs(&block : B -> _)
    satisfied = nil
    if yield @e
      satisfied = @e
    end
    satisfied
  end
end

class Rows
  def at(i : Int32) : Int32
    i &+ 13
  end

  def bsi(&)
    Rng.new(0, 2).bs { |i| yield at(i), i }
  end

  def bsx(&)
    bsi { |v, i| yield v }
  end
end

LibC.exit(Rows.new.bsx { |r| r > 9 } || 0)
CR

cat > control_untyped_block_param.cr <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

struct Rng(B, E)
  def initialize(@b : B, @e : E)
  end

  def bs(&)
    satisfied = nil
    if yield @e
      satisfied = @e
    end
    satisfied
  end
end

class Rows
  def at(i : Int32) : Int32
    i &+ 13
  end

  def bsi(&)
    Rng.new(0, 2).bs { |i| yield at(i), i }
  end

  def bsx(&)
    bsi { |v, i| yield v }.try { |i| i }
  end
end

LibC.exit(Rows.new.bsx { |r| r > 9 } || 0)
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

check chained_receiver_block 2
check chained_receiver_block_cast 2
check control_unchained 2
check control_untyped_block_param 2

[[ $fail == 0 ]] || exit 1
printf 'PASS receiver block yield binding\n'
