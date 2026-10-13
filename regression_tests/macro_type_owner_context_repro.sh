#!/usr/bin/env bash
# Regression: `@type` inside method-body macros must expand against the method's
# receiver type, not a placeholder or the lexical ancestor.
#  - `Sig.each { }` resolved to `Enum.each` and was inlined with
#    @current_class = Enum, so `{% for m in @type.constants %}` iterated nothing
#    (sum 0); the resolver also failed to walk an enum to its `Enum` parent.
#  - `{{ @type.constants.size }}` / `{{ @type.name.size }}` had no `@type` arm
#    in the macro value evaluator.
#  - MacroId delegated only a fixed method subset; every other method (e.g.
#    `@type.name.size`, `"ab".id.size`) returned nil instead of going through
#    StringLiteral as in the original MacroId#interpret.
#  - `{% if @type.name == "A" %}` inside a def was unevaluable by the
#    registry-only evaluator and both branches were dropped.
#  - `Sig::A.m { }` (enum member PATH receiver) was classified as a class call
#    on a type named `Sig::A`; the receiver-less lookup then picked the shared
#    `Enum#m` body, so `@type` in a yielding instance method expanded as Enum.
# ok cases print EXIT 7; the error case must fail to compile with the message.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_type_owner_context.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

HEAD_SRC='lib LibC
  fun exit(code : Int32) : NoReturn
end
'
ENUM_SRC='struct Enum
  def each(& : self ->)
    {% if @type.annotation(Flags) %}
      {% for member in @type.constants %}
        yield self.class.new({{@type.constant(member)}}), {{@type.constant(member)}}
      {% end %}
    {% else %}
      {% raise "Cannot iterate #{@type}: only Flags Enum can be iterated" %}
    {% end %}
  end

  def self.each(& : self ->)
    {% for member in @type.constants %}
      yield new({{@type.constant(member)}}), {{@type.constant(member)}}
    {% end %}
  end

  def self.cnt
    {{ @type.constants.size }}
  end
end

enum Sig
  A = 1
  B = 2
  C = 4
end

enum Col
  X = 3
  Y = 4
end
'

cat >"$WORK_DIR/ok_enum_class_each.cr" <<CR
$HEAD_SRC
$ENUM_SRC
sum = 0
Sig.each do |s|
  sum += s.value
end
LibC.exit(sum)
CR

cat >"$WORK_DIR/ok_enum_class_each_qualified.cr" <<CR
$HEAD_SRC
$ENUM_SRC
sum = 0
::Sig.each do |s|
  sum += s.value
end
LibC.exit(sum)
CR

# two receivers of one inherited inline body must not share an expansion
cat >"$WORK_DIR/ok_enum_class_each_two_enums.cr" <<CR
$HEAD_SRC
$ENUM_SRC
a = 0
Sig.each { |s| a += s.value }
b = 0
Col.each { |c| b += c.value }
LibC.exit(a == 7 && b == 7 ? 7 : 1)
CR

cat >"$WORK_DIR/ok_enum_constants_size.cr" <<CR
$HEAD_SRC
$ENUM_SRC
LibC.exit(Sig.cnt + Col.cnt + 2)
CR

cat >"$WORK_DIR/ok_instance_macro_if.cr" <<CR
$HEAD_SRC
class A
  def tag
    {% if @type.name == "A" %}7{% else %}1{% end %}
  end
end
LibC.exit(A.new.tag)
CR

cat >"$WORK_DIR/ok_class_method_macro_if_inherited.cr" <<CR
$HEAD_SRC
class A
  def self.tag
    x = {% if @type.name == "Bee" %}2{% else %}1{% end %}
    x
  end
end
class Bee < A
end
LibC.exit(A.tag == 1 && Bee.tag == 2 ? 7 : 1)
CR

cat >"$WORK_DIR/ok_class_method_type_name_inherited.cr" <<CR
$HEAD_SRC
class A
  def self.tag
    {{ @type.name.size }}
  end
end
class Bee < A
end
LibC.exit(Bee.tag * 2 + A.tag)
CR

cat >"$WORK_DIR/ok_macro_id_string_methods.cr" <<CR
$HEAD_SRC
class Foo
  def self.k : Int32
    {{ @type.name.downcase.size }} + {{ "ab".id.size }}
  end
end
LibC.exit(Foo.k + 2)
CR

BLOCK_NM_SRC='struct Enum
  def nm(&) : Int32
    yield self
    {{ @type.name.size }}
  end
end
'

# @type = Sig (size 3) through an enum member path receiver: 3 * 2 + 1
cat >"$WORK_DIR/ok_enum_block_method_type_name_path.cr" <<CR
$HEAD_SRC
$ENUM_SRC
$BLOCK_NM_SRC
LibC.exit(Sig::A.nm { |s| } * 2 + 1)
CR

# same through a local holding the member, plus a second enum: 3 + 3 + 1
cat >"$WORK_DIR/ok_enum_block_method_type_name_var.cr" <<CR
$HEAD_SRC
$ENUM_SRC
$BLOCK_NM_SRC
x = Sig::B
y = Col::Y
LibC.exit(x.nm { |s| } + y.nm { |c| } + 1)
CR

cat >"$WORK_DIR/err_instance_each_not_flags.cr" <<CR
$HEAD_SRC
$ENUM_SRC
sum = 0
Sig::A.each { |s| sum += s.value }
LibC.exit(sum)
CR

for name in ok_enum_class_each ok_enum_class_each_qualified ok_enum_class_each_two_enums \
    ok_enum_constants_size ok_instance_macro_if ok_class_method_macro_if_inherited \
    ok_class_method_type_name_inherited ok_macro_id_string_methods \
    ok_enum_block_method_type_name_path ok_enum_block_method_type_name_var; do
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

for pair in "err_instance_each_not_flags:Cannot iterate Sig"; do
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
echo macro_type_owner_context_repro_ok
