#!/usr/bin/env bash
# Regression: an enum's attached copy of `Enum#m` must stay the call target
# when another ancestor (`Object#m`) declares overloads of the same name.
#
# reject_inherited_alias_candidates dropped `F#m` (it shares its DefNode with
# `Enum#m`) unless the enum bucket covered the overloads of the whole ancestor
# chain. `Object#m` is never copied by attach_enum_instance_methods, so the
# per-enum copy was rejected and the call fell back to abstract `Enum#m`, whose
# macro body expanded for `Enum` (prelude: "method Enum#to_s must return
# String, but it is returning Nil | String" in DWARF Info#read_attribute_value).
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-enum_attached_overload_alias.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > object_zero_arg.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Object
  def tag : Int32
    1
  end
end
struct Enum
  def ===(other) : Bool
    false
  end
  def tag : Int32
    mn || 9
  end
  private def mn
    {% if @type.constants.size > 0 %} {{@type.constants.size}} {% else %} nil {% end %}
  end
end
enum F
  A = 1
  B = 2
  C = 3
end
LibC.exit(F::B.tag)
CR

cat > object_and_enum_overloads.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Object
  def tag(io : Int32) : Nil
  end
  def tag : Int32
    1
  end
end
struct Enum
  def ===(other) : Bool
    false
  end
  def tag(x : Int32) : Nil
  end
  def tag : Int32
    mn || 9
  end
  private def mn
    {% if @type.constants.size > 0 %} {{@type.constants.size}} {% else %} nil {% end %}
  end
end
enum F
  A = 1
  B = 2
  C = 3
end
LibC.exit(F::B.tag)
CR

cat > namespaced_to_s.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Object
  def to_s(io : Int32) : Nil
  end
  def to_s : Int32
    1
  end
end
struct Enum
  def ===(other) : Bool
    false
  end
  def to_s(x : Int32) : Nil
  end
  def to_s : Int32
    mn || 9
  end
  private def mn
    {% if @type.constants.size > 0 %} {{@type.constants.size}} {% else %} nil {% end %}
  end
end
module Crystal
  module DW
    enum FORM : UInt32
      A = 1
      B = 2
      C = 3
    end
    class Info
      def initialize(@k : Int32)
      end
      def rd(form)
        case form
        when FORM::A
          form = FORM.new(2_u32)
          rd(form)
        else
          form.to_s
        end
      end
    end
  end
end
LibC.exit(Crystal::DW::Info.new(1).rd(Crystal::DW::FORM::B))
CR

cat > no_object_overload.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Enum
  def ===(other) : Bool
    false
  end
  def tag(x : Int32) : Nil
  end
  def tag : Int32
    mn || 9
  end
  private def mn
    {% if @type.constants.size > 0 %} {{@type.constants.size}} {% else %} nil {% end %}
  end
end
enum F
  A = 1
  B = 2
  C = 3
end
LibC.exit(F::B.tag)
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

check object_zero_arg 3
check object_and_enum_overloads 3
check namespaced_to_s 3
check no_object_overload 3

[[ $fail == 0 ]] || exit 1
printf 'PASS enum_attached_overload_alias\n'
