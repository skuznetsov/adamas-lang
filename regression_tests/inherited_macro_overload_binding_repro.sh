#!/usr/bin/env bash
# Inherited @type expansion must follow the selected overload's receiver while
# ordinary overload bodies retain their declaring lexical namespace.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"

if [[ -n "${ADAMAS_INHERITED_MACRO_OVERLOAD_AUDIT_DIR:-}" ]]; then
  WORK_DIR="$ADAMAS_INHERITED_MACRO_OVERLOAD_AUDIT_DIR"
  mkdir -p "$WORK_DIR"
  KEEP_WORK_DIR=1
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited_macro_overload.XXXXXX")"
  KEEP_WORK_DIR=0
fi
if [[ "$KEEP_WORK_DIR" -eq 0 ]]; then
  trap 'rm -rf "$WORK_DIR"' EXIT
fi

cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun printf(format : UInt8*, ...) : Int32
end

class MacroFirstParent(T)
  TOKEN = 7

  def selected(value : String) : Int32
    {% if @type.name == "MacroFirstChild(Int32)" %}
      41
    {% else %}
      13
    {% end %}
  end

  def selected(value : Int32) : Int32
    TOKEN
  end

  def selected(value : Bool) : Int32
    5
  end
end

class MacroFirstChild(U) < MacroFirstParent(U)
  TOKEN = 90

  def selected(value : Bool) : Int32
    99
  end
end

class OrdinaryFirstParent(T)
  TOKEN = 7

  def selected(value : Int32) : Int32
    TOKEN
  end

  def selected(value : String) : Int32
    {% if @type.name == "OrdinaryFirstChild(Int32)" %}
      42
    {% else %}
      13
    {% end %}
  end

  def selected(value : Bool) : Int32
    5
  end
end

class OrdinaryFirstChild(U) < OrdinaryFirstParent(U)
  TOKEN = 90

  def selected(value : Bool) : Int32
    99
  end
end

class DefaultArityParent(T)
  TOKEN = 7

  def defaulted(value : Int32) : Int32
    TOKEN
  end

  def defaulted(value : String, bias : Int32 = 2) : Int32
    {% if @type.name == "DefaultArityChild(Int32)" %}
      60 + bias
    {% else %}
      30 + bias
    {% end %}
  end
end

class DefaultArityChild(U) < DefaultArityParent(U)
  TOKEN = 90
end

class OwnerTMacroFirst(T)
  TOKEN = 7

  def selected(value : T) : Int32
    {% if @type.name == "OwnerTMacroFirstChild(Int32)" %}
      71
    {% else %}
      11
    {% end %}
  end

  def selected(value : String) : Int32
    TOKEN
  end
end

class OwnerTMacroFirstChild(U) < OwnerTMacroFirst(U)
  TOKEN = 90
end

class OwnerTOrdinaryFirst(T)
  TOKEN = 7

  def selected(value : String) : Int32
    TOKEN
  end

  def selected(value : T) : Int32
    {% if @type.name == "OwnerTOrdinaryFirstChild(Int32)" %}
      72
    {% else %}
      12
    {% end %}
  end
end

class OwnerTOrdinaryFirstChild(U) < OwnerTOrdinaryFirst(U)
  TOKEN = 90
end

failures = 0

macro_parent = MacroFirstParent(Int32).new
macro_child = MacroFirstChild(Int32).new
failures |= 1 unless macro_parent.selected("x") == 13 && macro_child.selected("x") == 41
failures |= 2 unless macro_parent.selected(1) == 7 && macro_child.selected(1) == 7
failures |= 4 unless macro_parent.selected(true) == 5 && macro_child.selected(true) == 99

ordinary_parent = OrdinaryFirstParent(Int32).new
ordinary_child = OrdinaryFirstChild(Int32).new
failures |= 8 unless ordinary_parent.selected("x") == 13 && ordinary_child.selected("x") == 42
failures |= 16 unless ordinary_parent.selected(1) == 7 && ordinary_child.selected(1) == 7
failures |= 32 unless ordinary_parent.selected(true) == 5 && ordinary_child.selected(true) == 99

arity_parent = DefaultArityParent(Int32).new
arity_child = DefaultArityChild(Int32).new
failures |= 64 unless arity_parent.defaulted("x") == 32 && arity_child.defaulted("x") == 62 &&
                     arity_parent.defaulted("x", 4) == 34 && arity_child.defaulted("x", 4) == 64

owner_t_macro_first_parent = OwnerTMacroFirst(Int32).new
owner_t_macro_first_child = OwnerTMacroFirstChild(Int32).new
failures |= 128 unless owner_t_macro_first_parent.selected(1) == 11 &&
                      owner_t_macro_first_child.selected(1) == 71
failures |= 256 unless owner_t_macro_first_parent.selected("x") == 7 &&
                      owner_t_macro_first_child.selected("x") == 7

owner_t_ordinary_first_parent = OwnerTOrdinaryFirst(Int32).new
owner_t_ordinary_first_child = OwnerTOrdinaryFirstChild(Int32).new
failures |= 512 unless owner_t_ordinary_first_parent.selected(1) == 12 &&
                      owner_t_ordinary_first_child.selected(1) == 72
failures |= 1024 unless owner_t_ordinary_first_parent.selected("x") == 7 &&
                       owner_t_ordinary_first_child.selected("x") == 7

LibC.printf("FAILURE_MASK=%d\n", failures)
LibC.exit(failures == 0 ? 0 : 1)
CR

if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/build.resources" "$SAFE_RUN" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" \
    >"$WORK_DIR/build.log" 2>&1; then
  echo "inherited macro overload binding: compile failed" >&2
  tail -40 "$WORK_DIR/build.log" >&2
  exit 1
fi

RUN_SAFE_RESOURCE_FILE="$WORK_DIR/run.resources" \
  "$SAFE_RUN" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "inherited macro overload binding: comparisons failed (want EXIT 0):" >&2
  grep -E '^\[EXIT|^\[TIMEOUT|^\[KILLED' "$WORK_DIR/run.log" >&2 ||
    cat "$WORK_DIR/run.log" >&2
  exit 1
fi

echo inherited_macro_overload_binding_repro_ok
