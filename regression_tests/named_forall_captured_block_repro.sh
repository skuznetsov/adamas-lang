#!/usr/bin/env bash
# Regression: a call with named arguments and a captured block whose
# callback input names a method forall variable
# (`def named(box : Box(T), &callback : T -> Int32) forall T`, called as
# `named(box: Box.new(5)) { |a| a &+ 23 }`).
#
# The forall binder pairs named actuals with formals only through the selected
# call's formal-slot source binding. A block call never published that
# binding for deferred body lowering, and callback input inference called the
# binder without it, so both failed closed: the callee body was lowered with T
# unbound ("no overload matches 'Proc(Void, Int32)#call' with type Int32").
# The positional spelling `named(Box.new(5))` already worked.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-named_forall_captured_block.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > named_generic_restriction.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end
def named(box : Box(T), &callback : T -> Int32) forall T
  callback.call(box.value)
end
C.exit(named(box: Box.new(5)) { |a| a &+ 23 })
CR

cat > positional_then_named.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end
def two(a : Int32, box : Box(T), &cb : T -> Int32) forall T
  cb.call(box.value) &+ a
end
C.exit(two(1, box: Box.new(5)) { |x| x &+ 23 })
CR

cat > named_out_of_order_two_vars.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end
def pair(x : T, y : U, &cb : T, U -> Int32) forall T, U
  cb.call(x, y)
end
C.exit(pair(y: true, x: 3) { |a, b| b ? a &+ 10 : a })
CR

cat > named_inline_yield.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end
def yb(box : Box(T), &) forall T
  yield box.value
end
C.exit(yb(box: Box.new(7)) { |v| v &+ 1 })
CR

cat > named_direct_forall_value.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end
def direct(value : T, &cb : T -> Int32) forall T
  cb.call(value)
end
C.exit(direct(value: 4) { |v| v &+ 30 })
CR

cat > named_with_omitted_default.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end
def dflt(box : Box(T), k : Int32 = 2, &cb : T -> Int32) forall T
  cb.call(box.value) &* k
end
C.exit(dflt(box: Box.new(5)) { |v| v &+ 1 })
CR

cat > named_two_instantiations.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end
def twice(box : Box(T), &cb : T -> Int32) forall T
  cb.call(box.value) &+ cb.call(box.value)
end
a = twice(box: Box.new(3)) { |v| v &+ 1 }
b = twice(box: Box.new(true)) { |v| v ? 20 : 0 }
C.exit(a &+ b)
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

check named_generic_restriction 28
check positional_then_named 29
check named_out_of_order_two_vars 13
check named_inline_yield 8
check named_direct_forall_value 34
check named_with_omitted_default 12
check named_two_instantiations 48

[[ $fail == 0 ]] || exit 1
printf 'PASS named_forall_captured_block\n'
