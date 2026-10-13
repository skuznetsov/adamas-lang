#!/usr/bin/env bash
# Explicitly qualified calls must consult owner-scoped macros without letting
# a same-named global macro intercept ordinary class-method resolution. Owner,
# inherited, and included macros must still expand, while a child class method
# must shadow an inherited macro of the same name.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qualified_macro_owner_lookup.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

# A global macro that accepts the concurrent-style call shape. Its generated
# unqualified block call deliberately resolves to the ordinary global method.
def spawn(&block) : Int32
  99
end

macro spawn(call, *, name = nil, same_thread = false, &block)
  spawn do
    {{call}}
  end
end

module Crystal
  module System
    class Process
      def self.spawn(a : Int32, b : Int32, c : Int32, d : Int32,
                     e : Int32, f : Int32, g : Int32) : Int32
        42
      end
    end
  end
end

# Equal-arity global macro/method collision: owner resolution must win even
# when arity alone cannot reject the global macro.
def equal_collision(&block) : Int32
  99
end

macro equal_collision(call)
  equal_collision do
    {{call}}
  end
end

class EqualArityOwner
  def self.equal_collision(value : Int32) : Int32
    42
  end
end

class OwnerScopedMacro
  macro owner_value(call)
    77
  end
end

class MacroParent
  macro inherited_value(call)
    88
  end
end

class MacroInheritor < MacroParent
end

class MacroOverride < MacroParent
  def self.inherited_value(value : Int32) : Int32
    42
  end
end

module IncludedOwnerMacro
  macro included_value(call)
    89
  end
end

class IncludedMacroOwner
  include IncludedOwnerMacro
end

macro bare_global(call)
  99
end

seven_arg_collision_ok = Crystal::System::Process.spawn(1, 2, 3, 4, 5, 6, 7) == 42
equal_arity_collision_ok = EqualArityOwner.equal_collision(1) == 42
owner_macro_ok = OwnerScopedMacro.owner_value(1) == 77
inherited_macro_ok = MacroInheritor.inherited_value(1) == 88
inherited_method_shadow_ok = MacroOverride.inherited_value(1) == 42
included_macro_ok = IncludedMacroOwner.included_value(1) == 89
unqualified_global_macro_ok = bare_global(1) == 99

all_ok = seven_arg_collision_ok && equal_arity_collision_ok &&
         owner_macro_ok && inherited_macro_ok && inherited_method_shadow_ok &&
         included_macro_ok && unqualified_global_macro_ok
LibC.exit(all_ok ? 0 : 1)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" \
    >"$WORK_DIR/build.log" 2>&1; then
  echo "qualified macro owner lookup: compile failed" >&2
  tail -30 "$WORK_DIR/build.log" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 \
    >"$WORK_DIR/run.log" 2>&1; then
  echo "qualified macro owner lookup: runtime failed" >&2
  grep -E '^\[EXIT|^\[TIMEOUT|^\[KILLED' "$WORK_DIR/run.log" >&2 ||
    cat "$WORK_DIR/run.log" >&2
  exit 1
fi

if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "qualified macro owner lookup: aggregate comparison failed (want EXIT 0):" >&2
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi

echo qualified_macro_owner_lookup_repro_ok
