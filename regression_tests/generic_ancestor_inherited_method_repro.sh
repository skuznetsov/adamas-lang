#!/usr/bin/env bash
# Generic ancestor methods must be discovered and lowered on the requested
# receiver, with ancestor type parameters substituted per concrete child.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"

if [[ -n "${ADAMAS_GENERIC_ANCESTOR_AUDIT_DIR:-}" ]]; then
  WORK_DIR="$ADAMAS_GENERIC_ANCESTOR_AUDIT_DIR"
  mkdir -p "$WORK_DIR"
  KEEP_WORK_DIR=1
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_ancestor_inherited.XXXXXX")"
  KEEP_WORK_DIR=0
fi
if [[ "$KEEP_WORK_DIR" -eq 0 ]]; then
  trap 'rm -rf "$WORK_DIR"' EXIT
fi

cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class GenericRoot(T)
  TOKEN = 7

  def inherited_macro : Int32
    {% if @type.name == "GenericRoot(Int32)" %}
      10
    {% elsif @type.name == "DirectChild(Int32)" %}
      15
    {% elsif @type.name == "GenericParent(Int32)" %}
      16
    {% elsif @type.name == "GenericChild(Int32)" %}
      20
    {% elsif @type.name == "GenericChild(Float64)" %}
      21
    {% elsif @type.name == "Grandchild(Int32)" %}
      30
    {% elsif @type.name == "Grandchild(Float64)" %}
      31
    {% elsif @type.name == "RenamedChild(Float64)" %}
      42
    {% else %}
      1
    {% end %}
  end

  # Zero actual arguments can select a defaulted signature; a splat keeps its
  # formal signature on the ordinary nonempty call path.
  def inherited_macro_defaulted(value : Int32 = 4) : Int32
    {% if @type.name == "DirectChild(Int32)" %}
      55
    {% else %}
      50
    {% end %}
  end

  def inherited_macro_splat(*values : Int32) : Int32
    {% if @type.name == "DirectChild(Int32)" %}
      65 + values[0] - 4
    {% else %}
      60 + values[0] - 4
    {% end %}
  end

  def inherited_macro_splat_pair(*values : Int32) : Int32
    {% if @type.name == "DirectChild(Int32)" %}
      65 + values[0] + values[1] - 9
    {% else %}
      60 + values[0] + values[1] - 9
    {% end %}
  end

  def inherited_ordinary(value : T) : T
    value
  end

  def inherited_constant : Int32
    TOKEN
  end

  def inherited_overload(value : T) : Int32
    40
  end

  def inherited_overload(value : String) : Int32
    41
  end

  # Keep a macro-bearing generic overload next to a non-macro overload with
  # the same name. Receiver preservation must follow the overload actually
  # selected for this call, not a same-name template scan.
  def inherited_macro_overload(value : T) : Int32
    {% if @type.name == "GenericRoot(Int32)" %}
      70
    {% elsif @type.name == "DirectChild(Int32)" %}
      75
    {% elsif @type.name == "GenericChild(Int32)" %}
      80
    {% elsif @type.name == "GenericChild(Float64)" %}
      81
    {% else %}
      1
    {% end %}
  end

  def inherited_macro_overload(value : String) : Int32
    TOKEN
  end

  def inherited_lexical_and_macro : Int32
    TOKEN + inherited_macro
  end

  def shadowed : Int32
    60
  end
end

class DirectChild(U) < GenericRoot(U)
  TOKEN = 90
end

class GenericParent(U) < GenericRoot(U)
end

class GenericChild(V) < GenericParent(V)
  TOKEN = 90

  def child_owned : Int32
    50
  end

  def child_constant : Int32
    TOKEN
  end

  def inherited_overload(value : String) : Int32
    61
  end

  def shadowed : Int32
    51
  end
end

class Grandchild(W) < GenericChild(W)
  TOKEN = 91
end

# This changes the child's generic parameter name relative to the ancestor.
class RenamedChild(U) < GenericRoot(U)
  TOKEN = 92
end

class FixedParent(T)
  def fixed_value(value : T) : T
    value
  end
end

class FixedChild(U) < FixedParent(String)
end

module QualifiedParents
  class Root(T)
    def nested_value(value : T) : T
      value
    end
  end
end

class PairRoot(A, B)
  def first(value : A) : A
    value
  end

  def second(value : B) : B
    value
  end
end

# Parent parameter order is intentionally different from the child order.
class PermutedChild(U, V) < PairRoot(V, U)
end

# Nested generic arguments and an absolute qualified parent path must survive
# parsing and child substitution as one exact parent application.
class AbsoluteNestedChild(U) < ::QualifiedParents::Root(Tuple(U, Int64))
end

class LayoutParent(T)
  @value : T

  def initialize(@value : T)
  end

  def inherited_value : T
    @value
  end
end

class LayoutChild(U) < LayoutParent(U)
  @extra : Int64 = 0x1234_5678_9abc_def0_i64

  def extra : Int64
    @extra
  end
end

failures = 0

failures += 1 unless GenericRoot(Int32).new.inherited_macro == 10
failures += 1 unless DirectChild(Int32).new.inherited_macro == 15
failures += 1 unless GenericRoot(Int32).new.inherited_macro_defaulted == 50
failures += 1 unless DirectChild(Int32).new.inherited_macro_defaulted == 55
failures += 1 unless GenericRoot(Int32).new.inherited_macro_splat(4) == 60
failures += 1 unless DirectChild(Int32).new.inherited_macro_splat(4) == 65
failures += 1 unless GenericRoot(Int32).new.inherited_macro_splat(5, 4) == 61
failures += 1 unless DirectChild(Int32).new.inherited_macro_splat(5, 4) == 66
failures += 1 unless GenericRoot(Int32).new.inherited_macro_splat_pair(4, 5) == 60
failures += 1 unless DirectChild(Int32).new.inherited_macro_splat_pair(4, 5) == 65
failures += 1 unless GenericRoot(Int32).new.inherited_macro_splat_pair(4, 6, 7) == 61
failures += 1 unless DirectChild(Int32).new.inherited_macro_splat_pair(4, 6, 7) == 66
failures += 1 unless GenericParent(Int32).new.inherited_macro == 16
failures += 1 unless GenericChild(Int32).new.inherited_macro == 20
failures += 1 unless GenericChild(Float64).new.inherited_macro == 21
failures += 1 unless Grandchild(Int32).new.inherited_macro == 30
failures += 1 unless Grandchild(Float64).new.inherited_macro == 31
failures += 1 unless RenamedChild(Float64).new.inherited_macro == 42

int_child = GenericChild(Int32).new
float_child = GenericChild(Float64).new
failures += 1 unless DirectChild(Int32).new.inherited_ordinary(9) == 9
failures += 1 unless int_child.inherited_ordinary(9) == 9
failures += 1 unless float_child.inherited_ordinary(9.5) == 9.5
failures += 1 unless RenamedChild(Float64).new.inherited_ordinary(8.5) == 8.5
failures += 1 unless Grandchild(Float64).new.inherited_ordinary(7.5) == 7.5

# Inherited method bodies resolve constants in their declaring namespace even
# when the concrete receiver shadows that name; child-owned bodies stay local.
failures += 1 unless GenericRoot(Int32).new.inherited_constant == 7
failures += 1 unless DirectChild(Int32).new.inherited_constant == 7
failures += 1 unless int_child.inherited_constant == 7
failures += 1 unless float_child.inherited_constant == 7
failures += 1 unless int_child.child_constant == 90

# Alternate the sibling instantiations to catch a base-keyed type-map leak.
failures += 1 unless int_child.inherited_overload(9) == 40
failures += 1 unless float_child.inherited_overload(9.5) == 40
failures += 1 unless int_child.inherited_overload(10) == 40
failures += 1 unless float_child.inherited_overload(10.5) == 40

failures += 1 unless DirectChild(Int32).new.inherited_overload(9) == 40
failures += 1 unless DirectChild(Int32).new.inherited_overload("x") == 41
failures += 1 unless int_child.inherited_overload("x") == 61
failures += 1 unless float_child.inherited_overload("x") == 61
failures += 1 unless RenamedChild(Float64).new.inherited_overload("x") == 41
failures += 1 unless Grandchild(Float64).new.inherited_overload("x") == 61

failures += 1 unless GenericRoot(Int32).new.inherited_macro_overload(9) == 70
failures += 1 unless DirectChild(Int32).new.inherited_macro_overload(9) == 75
failures += 1 unless int_child.inherited_macro_overload(9) == 80
failures += 1 unless float_child.inherited_macro_overload(9.5) == 81
# This selects the ordinary String overload; its constant remains parent-lexical.
failures += 1 unless DirectChild(Int32).new.inherited_macro_overload("x") == 7
failures += 1 unless int_child.inherited_macro_overload("x") == 7

failures += 1 unless int_child.child_owned == 50
failures += 1 unless int_child.shadowed == 51
failures += 1 unless Grandchild(Int32).new.shadowed == 51
failures += 1 unless DirectChild(Int32).new.shadowed == 60

# The ancestor's constant stays lexical even though @type follows the receiver.
failures += 1 unless GenericRoot(Int32).new.inherited_lexical_and_macro == 17
failures += 1 unless DirectChild(Int32).new.inherited_lexical_and_macro == 22
failures += 1 unless GenericParent(Int32).new.inherited_lexical_and_macro == 23
failures += 1 unless int_child.inherited_lexical_and_macro == 27
failures += 1 unless float_child.inherited_lexical_and_macro == 28
failures += 1 unless Grandchild(Int32).new.inherited_lexical_and_macro == 37
failures += 1 unless Grandchild(Float64).new.inherited_lexical_and_macro == 38
failures += 1 unless RenamedChild(Float64).new.inherited_lexical_and_macro == 49

# A fixed parent argument and a permuted multi-parameter parent application
# must survive child specialization without positional-name inference.
failures += 1 unless FixedChild(Int32).new.fixed_value("fixed") == "fixed"
permuted = PermutedChild(Int32, Float64).new
failures += 1 unless permuted.first(1.25) == 1.25
failures += 1 unless permuted.second(9) == 9

nested = AbsoluteNestedChild(Float64).new
nested_value = {3.25, 0x7654_3210_fedc_ba98_i64}
failures += 1 unless nested.nested_value(nested_value) == nested_value

# Parent ivar layout and inherited construction/access use the concrete parent
# arguments; the child's extra field also checks that parent storage was copied.
layout_int = LayoutChild(Int64).new(0x2345_6789_abcd_ef01_i64)
layout_float = LayoutChild(Float64).new(13.25)
failures += 1 unless layout_int.inherited_value == 0x2345_6789_abcd_ef01_i64
failures += 1 unless layout_float.inherited_value == 13.25
failures += 1 unless layout_int.extra == 0x1234_5678_9abc_def0_i64
failures += 1 unless layout_float.extra == 0x1234_5678_9abc_def0_i64

LibC.exit(failures == 0 ? 0 : 1)
CR

if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/build.resources" "$SAFE_RUN" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" \
    >"$WORK_DIR/build.log" 2>&1; then
  echo "generic ancestor inherited method: compile failed" >&2
  tail -40 "$WORK_DIR/build.log" >&2
  exit 1
fi

RUN_SAFE_RESOURCE_FILE="$WORK_DIR/run.resources" \
  "$SAFE_RUN" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "generic ancestor inherited method: comparisons failed (want EXIT 0):" >&2
  grep -E '^\[EXIT|^\[TIMEOUT|^\[KILLED' "$WORK_DIR/run.log" >&2 ||
    cat "$WORK_DIR/run.log" >&2
  exit 1
fi

echo generic_ancestor_inherited_method_repro_ok
