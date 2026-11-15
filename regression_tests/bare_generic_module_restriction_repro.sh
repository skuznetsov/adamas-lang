#!/usr/bin/env bash
# Regression: a bare generic module restriction admits every application of
# the module.
#
# `def cat(other : Ind)` with `module Ind(T)` must accept a class that
# includes `Ind(T)` or `Ind(Int32)`, as Crystal does (`Array#concat(other :
# Indexable)` for `[1].concat([2])`). The source module matcher accepted a
# bare restriction only for a non-generic application, so every such call
# failed with "no overload matches", or fell through to an unrestricted
# overload. Restrictions with arguments, non-generic modules, an unrelated
# class and a different generic module are controls.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-bare_generic_module_restriction.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > bare_restriction_generic_includer.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind(T)
end
class Arr(T)
  include Ind(T)
  def initialize(@v : T); end
  def cat(other : Ind) : Int32
    10
  end
end
a = Arr(Int32).new(1)
LibC.exit(a.cat(Arr(Int32).new(2)))
CR

cat > bare_restriction_other_receiver.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind(T)
end
class Arr(T)
  include Ind(T)
  def initialize(@v : T); end
end
class Box
  def cat(other : Ind) : Int32
    10
  end
end
LibC.exit(Box.new.cat(Arr(Int32).new(2)))
CR

cat > bare_restriction_local_argument.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind(T)
end
class Arr(T)
  include Ind(T)
  def initialize(@v : T); end
  def cat(other : Ind) : Int32
    10
  end
end
a = Arr(Int32).new(1)
b = Arr(Int32).new(2)
LibC.exit(a.cat(b))
CR

cat > bare_restriction_concrete_application.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind(T)
end
class Arr
  include Ind(Int32)
end
class Box
  def cat(other : Ind) : Int32
    10
  end
end
LibC.exit(Box.new.cat(Arr.new))
CR

cat > bare_restriction_beats_unrestricted.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind(T)
end
class Arr(T)
  include Ind(T)
  def initialize(@v : T); end
end
class Box
  def cat(other : Ind) : Int32
    10
  end
  def cat(other) : Int32
    20
  end
end
LibC.exit(Box.new.cat(Arr(Int32).new(2)))
CR

cat > indexable_enumerable_overloads.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Enu(T)
  def sz; 1; end
end
module Ind(T)
  include Enu(T)
end
module Ind::Mut(T)
  include Ind(T)
end
class Arr(T)
  include Ind::Mut(T)
  def initialize(@v : T); end
  def v; @v; end
  def cat(other : Ind) : Int32
    10
  end
  def cat(other : Enu) : Int32
    20
  end
end
a = Arr(Int32).new(1)
LibC.exit(a.cat(Arr(Int32).new(2)))
CR

cat > transitive_bare_enumerable_only.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Enu(T)
  def sz; 1; end
end
module Ind(T)
  include Enu(T)
end
module Ind::Mut(T)
  include Ind(T)
end
class Arr(T)
  include Ind::Mut(T)
  def initialize(@v : T); end
  def v; @v; end
  def cat(other : Enu) : Int32
    20
  end
end
a = Arr(Int32).new(1)
LibC.exit(a.cat(Arr(Int32).new(2)))
CR

cat > transitive_module_chain.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Enu(T)
  def sz; 1; end
end
module Ind(T)
  include Enu(T)
end
module Mut(T)
  include Ind(T)
end
class Arr(T)
  include Mut(T)
  def initialize(@v : T); end
  def v; @v; end
  def cat(other : Ind) : Int32
    10
  end
  def cat(other : Enu) : Int32
    20
  end
end
a = Arr(Int32).new(1)
LibC.exit(a.cat(Arr(Int32).new(2)))
CR

cat > applied_restriction_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind(T)
end
class Arr(T)
  include Ind(T)
  def initialize(@v : T); end
  def cat(other : Ind(T)) : Int32
    10
  end
end
a = Arr(Int32).new(1)
LibC.exit(a.cat(Arr(Int32).new(2)))
CR

cat > non_generic_module_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind
end
class Arr(T)
  include Ind
  def initialize(@v : T); end
end
class Box
  def cat(other : Ind) : Int32
    10
  end
end
LibC.exit(Box.new.cat(Arr(Int32).new(2)))
CR

cat > unrelated_class_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind(T)
end
class Arr(T)
  include Ind(T)
  def initialize(@v : T); end
end
class Other
end
class Box
  def cat(other : Ind) : Int32
    10
  end
  def cat(other) : Int32
    20
  end
end
LibC.exit(Box.new.cat(Other.new))
CR

cat > different_generic_module_control.cr <<'CR'
struct Int32; def ===(other : Int32) : Bool; self == other; end; end
lib LibC
  fun exit(c : Int32) : NoReturn
end
module Ind(T)
end
module Ind2(T)
end
class Arr(T)
  include Ind2(T)
  def initialize(@v : T); end
end
class Box
  def cat(other : Ind) : Int32
    10
  end
  def cat(other) : Int32
    20
  end
end
LibC.exit(Box.new.cat(Arr(Int32).new(1)))
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

check bare_restriction_generic_includer 10
check bare_restriction_other_receiver 10
check bare_restriction_local_argument 10
check bare_restriction_concrete_application 10
check bare_restriction_beats_unrestricted 10
check indexable_enumerable_overloads 10
check transitive_bare_enumerable_only 20
check transitive_module_chain 10
check applied_restriction_control 10
check non_generic_module_control 10
check unrelated_class_control 20
check different_generic_module_control 20

[[ $fail == 0 ]] || exit 1
printf 'PASS bare_generic_module_restriction\n'
