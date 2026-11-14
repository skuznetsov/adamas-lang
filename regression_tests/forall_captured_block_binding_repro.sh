#!/usr/bin/env bash
# Regression: a captured block whose callback inputs name a method forall
# variable (`def named(value : T, &callback : T -> _) forall T`, or a generic
# restriction such as `box : Box(T)`) must see T bound by the call's ordinary
# arguments, at the callsite and in the callee body.
#
# The callsite bound forall variables for block inputs only for included Defs,
# so the block saw a bare `T`: its result was not inferable and the call forced
# the unbound base body ("no overload matches 'Proc(Void, Void)#call'"). The
# callee was keyed by block arity (`named$block$arity1`) unless a regular param
# was untyped, so a `T`-spelled or `Box(T)` restriction was lowered with T
# unbound ("no overload matches 'Proc(Void, Int32)#call' with type Int32").
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-forall_captured_block_binding.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > bare_forall_open_result.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
def named(value : T, &callback : T -> _) forall T
  callback.call(value)
end
C.exit(named(5) { |a| a &+ 23 })
CR

cat > bare_forall_fixed_result.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
def named(value : T, &callback : T -> Int32) forall T
  callback.call(value)
end
C.exit(named(5) { |a| a &+ 23 })
CR

cat > bare_forall_two_shapes.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
def named(value : T, &callback : T -> Int32) forall T
  callback.call(value)
end
C.exit(named(5) { |a| a &+ 3 } &+ named(20_i64) { |a| a.to_i32! })
CR

cat > generic_restriction_fixed_result.cr <<'CR'
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
C.exit(named(Box.new(5)) { |a| a &+ 23 })
CR

cat > generic_restriction_two_shapes.cr <<'CR'
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
C.exit(named(Box.new(5)) { |a| a &+ 3 } &+ named(Box.new(20_i64)) { |a| a.to_i32! })
CR

cat > generic_restriction_two_formals.cr <<'CR'
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
class Pair(A, B)
  def initialize(@a : A, @b : B)
  end

  def b : B
    @b
  end
end
def pick(pair : Pair(A, B), &callback : B -> Int32) forall A, B
  callback.call(pair.b)
end
C.exit(pick(Pair.new(1_i64, 5)) { |b| b &+ 23 })
CR

cat > generic_restriction_open_result.cr <<'CR'
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
def named(box : Box(T), &callback : T -> _) forall T
  callback.call(box.value)
end
C.exit(named(Box.new(5)) { |a| a &+ 23 })
CR

cat > nested_generic_restriction.cr <<'CR'
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
C.exit(named(Box.new(Box.new(5))) { |a| a.value &+ 23 })
CR

cat > instance_forall_class_and_instance.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Answer
  def self.code : Int32
    42
  end

  def code : Int32
    7
  end
end
class Projector
  def raw(value : T, & : T -> _) forall T
    yield value
  end
  def named(value : T, &callback : T -> _) forall T
    callback.call(value)
  end
end
def invoke(&block : -> Int32)
  block.call
end
projector = Projector.new
C.exit(1) unless invoke { projector.raw(Answer) { |answer| answer.code } } == 42
C.exit(2) unless invoke { projector.named(Answer) { |answer| answer.code } } == 42
C.exit(3) unless invoke { projector.named(Answer.new) { |answer| answer.code } } == 7
C.exit(0)
CR

cat > instance_forall_class_value.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Answer
  def self.code : Int32
    42
  end

  def code : Int32
    7
  end
end
class Projector
  def raw(value : T, & : T -> _) forall T
    yield value
  end
  def named(value : T, &callback : T -> _) forall T
    callback.call(value)
  end
end
def invoke(&block : -> Int32)
  block.call
end
projector = Projector.new
C.exit(2) unless projector.named(Answer) { |answer| answer.code } == 42
C.exit(0)
CR

cat > instance_forall_instance_value.cr <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Answer
  def self.code : Int32
    42
  end

  def code : Int32
    7
  end
end
class Projector
  def raw(value : T, & : T -> _) forall T
    yield value
  end
  def named(value : T, &callback : T -> _) forall T
    callback.call(value)
  end
end
def invoke(&block : -> Int32)
  block.call
end
projector = Projector.new
C.exit(2) unless projector.named(Answer.new) { |answer| answer.code } == 7
C.exit(0)
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

check bare_forall_open_result 28
check bare_forall_fixed_result 28
check bare_forall_two_shapes 28
check generic_restriction_fixed_result 28
check generic_restriction_two_shapes 28
check generic_restriction_two_formals 28
check generic_restriction_open_result 28
check nested_generic_restriction 28
check instance_forall_class_and_instance 0
check instance_forall_class_value 0
check instance_forall_instance_value 0

[[ $fail == 0 ]] || exit 1
printf 'PASS forall_captured_block_binding\n'
