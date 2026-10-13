#!/usr/bin/env bash
# Regression: a non-control macro statement `{% expr %}` at statement position
# inside a def body was lowered as RUNTIME code (parse_percent_macro_control
# returned PREFIX_ERROR for any keyword outside if/unless/for/while/begin/...
# after consuming `{%`, so `raise "bad" unless T == Int32` and `LibC.exit(9)`
# ran as ordinary Crystal). Now they parse to MacroExpressionNode(output=false)
# and are evaluated at compile time: a taken `raise` is a compile error
# (non-zero exit + message), a not-taken or unevaluable one has no effect, and
# nothing is ever emitted as runtime code. `@type` in such statements is the
# def's receiver type, and top-level raises interpolate constants.
# ok cases print EXIT 7; error cases must fail to compile with the message.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_raise_statement.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

HEAD_SRC='lib LibC
  fun exit(code : Int32) : NoReturn
end
'

# not taken: guard false for T == Int32
cat >"$WORK_DIR/ok_not_taken.cr" <<CR
$HEAD_SRC
struct S(T)
  def f : Int32
    {% raise "bad" unless T == Int32 %}
    7
  end
end
LibC.exit(S(Int32).new.f)
CR

# macro statement must not run as runtime code (would exit 9)
cat >"$WORK_DIR/ok_not_runtime.cr" <<CR
$HEAD_SRC
def f : Int32
  {% LibC.exit(9) %}
  7
end
LibC.exit(f)
CR

# macro variable assignment statement keeps working
cat >"$WORK_DIR/ok_assign.cr" <<CR
$HEAD_SRC
def f : Int32
  {% n = 5 %}
  7
end
LibC.exit(f)
CR

# postfix if with a false guard
cat >"$WORK_DIR/ok_if_false.cr" <<CR
$HEAD_SRC
struct S(T)
  def f : Int32
    {% raise "bad" if T == String %}
    7
  end
end
LibC.exit(S(Int32).new.f)
CR

# fail-open: unevaluable guard must not error
cat >"$WORK_DIR/ok_unevaluable.cr" <<CR
$HEAD_SRC
struct S(T)
  def f : Int32
    {% raise "bad" if some_unknown_macro_thing(T) %}
    7
  end
end
LibC.exit(S(Int32).new.f)
CR

# taken: guard true (T is Int32, not String)
cat >"$WORK_DIR/err_taken.cr" <<CR
$HEAD_SRC
struct S(T)
  def f : Int32
    {% raise "boom_taken" unless T == String %}
    7
  end
end
LibC.exit(S(Int32).new.f)
CR

cat >"$WORK_DIR/err_unconditional.cr" <<CR
$HEAD_SRC
def f : Int32
  {% raise "boom_uncond" %}
  7
end
LibC.exit(f)
CR

# `@type` in a def-body raise / guard expands to the receiver type
cat >"$WORK_DIR/err_type_interp.cr" <<CR
$HEAD_SRC
class Foo
  def bar
    {% raise "Can't iterate #{@type}: x" %}
    1
  end
end
Foo.new.bar
LibC.exit(7)
CR

cat >"$WORK_DIR/err_type_guard_suffix.cr" <<CR
$HEAD_SRC
class Foo
  def bar
    {% raise "boom_suffix" unless @type.name == "Bar" %}
    1
  end
end
Foo.new.bar
LibC.exit(7)
CR

cat >"$WORK_DIR/err_type_guard_block.cr" <<CR
$HEAD_SRC
class Foo
  def bar
    {% unless @type.name == "Bar"; raise "boom_block"; end %}
    1
  end
end
Foo.new.bar
LibC.exit(7)
CR

cat >"$WORK_DIR/ok_type_guard_suffix.cr" <<CR
$HEAD_SRC
class Bar
  def bar
    {% raise "boom_suffix" unless @type.name == "Bar" %}
    7
  end
end
LibC.exit(Bar.new.bar)
CR

cat >"$WORK_DIR/ok_type_guard_block.cr" <<CR
$HEAD_SRC
class Bar
  def bar
    {% unless @type.name == "Bar"; raise "boom_block"; end %}
    7
  end
end
LibC.exit(Bar.new.bar)
CR

# top-level raise with constant and arithmetic interpolation
cat >"$WORK_DIR/err_toplevel_interp.cr" <<CR
$HEAD_SRC
X = 5
{% raise "val #{X} and #{1 + 2}" %}
LibC.exit(7)
CR

for name in ok_not_taken ok_not_runtime ok_assign ok_if_false ok_unevaluable \
    ok_type_guard_suffix ok_type_guard_block; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    echo "case $name: compile failed" >&2
    tail -20 "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 7\]' "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT 7):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done

for pair in "err_taken:boom_taken" "err_unconditional:boom_uncond" "err_type_interp:iterate Foo" \
    "err_type_guard_suffix:boom_suffix" "err_type_guard_block:boom_block" \
    "err_toplevel_interp:val 5 and 3"; do
  name="${pair%%:*}"
  msg="${pair##*:}"
  rc=0
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && [ -x "$WORK_DIR/$name" ]; then
    echo "case $name: compile unexpectedly succeeded (want compile error)" >&2
    exit 1
  fi
  if ! grep -q "$msg" "$WORK_DIR/$name.build.log"; then
    echo "case $name: compile error lacks message '$msg':" >&2
    tail -20 "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
done
echo macro_raise_statement_repro_ok
