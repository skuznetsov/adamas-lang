#!/usr/bin/env bash
# Regression: macro `==` / `!=` on non-numeric values (StringLiteral, SymbolLiteral,
# MacroId, BoolLiteral, mixed number/string). The macro interpreter had no `==`
# arm except for numbers and MacroId, so `{% if side == "right" %}` was always
# false and `!=` was false too. S1 then dropped the `side == "right"` block in
# ast_to_hir lower_binary, and S2 printed enum operands of `<<` as integers.
# Each mismatching case sets one exit-code bit.
#
# Second program (x2): structural equality must match the original
# macros/methods.cr: CharLiteral != StringLiteral, NumberLiteral compares
# value AND kind (`1_i32 != 1_i64`, `1_000 == 1000`), MacroId only equals
# String/Symbol by value (`1.id != 1`), ArrayLiteral compares elementwise.
# Both the `{% if %}` condition path and the `{{ }}` value path are checked;
# def-body `{% if %}` goes through the HIR condition evaluator, which delegates
# literal-only conditions to the macro interpreter.
# Third program (x3): the same at top level (lower_macro_expression path),
# plus `&&`/`||` in the `{{ }}` value path, which must short-circuit and yield
# an operand like the original interpreter visit(And)/visit(Or).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_string_equality.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/x.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def loop_eq(left_v : Int32, right_v : Int32) : Int32
  r = 0
  {% for side in ["left", "right"] %}
    {% if side == "right" %}
      r += 10
    {% end %}
    {% if side != "right" %}
      r += 100
    {% end %}
    r += {{side.id}}_v
  {% end %}
  r
end

def code : Int32
  c = 0
  c |= 1 unless loop_eq(1, 2) == 113
  c |= 2 unless {{ "a" == "a" }}
  c |= 4 unless {{ "a" != "b" }}
  c |= 8 if {{ "a" == "b" }}
  c |= 16 unless {{ :sym == :sym }}
  c |= 32 unless {{ "x" == "x".id }}
  c |= 64 unless {{ true == true }}
  c |= 128 unless {{ 1 != "1" }}
  c
end

LibC.exit(code)
CR

cat > "$WORK_DIR/x2.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

# Two-sided: every condition must take exactly one branch. A condition the
# def-body evaluator cannot evaluate drops both branches, which leaves its bit
# out of `t | f` and fails instead of passing by omission.
# Expected truth mask (host Crystal oracle): 2|16|32|64 = 114.
def code : Int32
  t = 0
  f = 0
  {% if 'x' == "x" %} t |= 1 {% else %} f |= 1 {% end %}
  t |= 2 if {{ [1_000] == [1000] }}
  f |= 2 unless {{ [1_000] == [1000] }}
  {% if 1_i32 == 1_i64 %} t |= 4 {% else %} f |= 4 {% end %}
  {% if 1.id == 1 %} t |= 8 {% else %} f |= 8 {% end %}
  {% unless "foo=".id.ends_with?('=') %} f |= 16 {% else %} t |= 16 {% end %}
  {% if [1, 2].size == 2 && 1_000 == 1000 && 'x' == 'x' %} t |= 32 {% else %} f |= 32 {% end %}
  {% if 'x'.stringify == "'x'" %} t |= 64 {% else %} f |= 64 {% end %}
  {% if 'x' == "x" || 1_i32 == 1_i64 || [1] == [2] %} t |= 128 {% else %} f |= 128 {% end %}
  (t ^ 114) | (255 & ~(t | f))
end

LibC.exit(code)
CR

cat > "$WORK_DIR/x3.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
c = 0
c |= 1 if {{ 'x' == "x" }}
c |= 2 unless {{ [1_000] == [1000] }}
c |= 4 if {{ 1_i32 == 1_i64 }}
c |= 8 if {{ 1.id == 1 || 1 == 1.id }}
c |= 16 unless {{ ([] of Int32) == ([] of String) }}
c |= 32 unless {{ "x" == "x".id && :x == "x".id }}
c |= 64 unless {{ nil == nil && true != false && [1, 2] != [1, 3] }}
c |= 128 unless {{ (nil || 7) == 7 && (false && 1) == false }}
LibC.exit(c)
CR

for prog in x x2 x3; do
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 "$WORK_DIR/$prog.cr" --no-prelude -o "$WORK_DIR/$prog" > "$WORK_DIR/compile.log" 2>&1; then
  echo "FAIL: $prog compile failed"
  tail -20 "$WORK_DIR/compile.log"
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$prog" 5 512 > "$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "FAIL: $prog macro equality evaluated wrong"
  cat "$WORK_DIR/run.log"
  exit 1
fi
done
echo "PASS"
