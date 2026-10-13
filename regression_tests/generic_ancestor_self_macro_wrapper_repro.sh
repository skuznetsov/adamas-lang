#!/usr/bin/env bash
# Inherited wrappers must retain the child self type for nested macro calls,
# while ordinary overloads, lexical constants and other receivers stay exact.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_ancestor_self_macro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
  fun exit(status : Int32) : NoReturn
end

class ControlRoot(T)
  TOKEN = 7

  def macro_zero : Int32
    {% if @type.name == "ControlChild(Int32)" %}
      20
    {% else %}
      10
    {% end %}
  end

  def wrap_bare : Int32
    macro_zero
  end

  def wrap_parens : Int32
    macro_zero()
  end

  def wrap_self : Int32
    self.macro_zero
  end

  def wrap_add : Int32
    TOKEN + macro_zero
  end

  def wrap_add_parens : Int32
    TOKEN + macro_zero()
  end

  def wrap_add_self : Int32
    TOKEN + self.macro_zero
  end

  def mixed(value : Int32) : Int32
    {% if @type.name == "ControlChild(Int32)" %}
      40
    {% else %}
      30
    {% end %}
  end

  def mixed(value : String) : Int32
    TOKEN
  end

  def wrap_mixed(value : Int32) : Int32
    TOKEN + mixed(value)
  end

  def wrap_mixed(value : String) : Int32
    TOKEN + mixed(value)
  end

  def wrap_peer(peer : ControlRoot(Int32)) : Int32
    TOKEN + peer.macro_zero
  end
end

class ControlChild(U) < ControlRoot(U)
  TOKEN = 90
end

parent = ControlRoot(Int32).new
child = ControlChild(Int32).new
mask = 0
mask |= 1 unless parent.wrap_add == 17
mask |= 2 unless child.wrap_bare == 20
mask |= 4 unless child.wrap_parens == 20
mask |= 8 unless child.wrap_self == 20
mask |= 16 unless child.wrap_add == 27
mask |= 32 unless child.wrap_add_parens == 27
mask |= 64 unless child.wrap_add_self == 27
mask |= 128 unless parent.wrap_mixed(1) == 37
mask |= 256 unless child.wrap_mixed(1) == 47
mask |= 512 unless parent.wrap_mixed("x") == 14
mask |= 1024 unless child.wrap_mixed("x") == 14
mask |= 2048 unless child.wrap_peer(parent) == 17
LibC.printf("FAILURE_MASK=%d\n", mask)
LibC.exit(mask == 0 ? 0 : 1)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" \
    >"$WORK_DIR/build.log" 2>&1; then
  echo "FAIL: inherited self-macro wrapper fixture did not compile" >&2
  tail -30 "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 \
  >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^FAILURE_MASK=0$' "$WORK_DIR/run.log" || \
   ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "FAIL: inherited self-macro wrapper control failed" >&2
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo "PASS: inherited self-macro wrappers preserve child identity and lexical controls"
