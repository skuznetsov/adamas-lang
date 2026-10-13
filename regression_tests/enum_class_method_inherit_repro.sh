#!/usr/bin/env bash
# Regression: an `Enum` CLASS method called on a concrete enum (`Sig.each`)
# resolved to the per-enum INSTANCE method `Sig#each` (instance methods are
# attached per enum, class methods were not), so the instance body's
# `{% raise "Can't iterate #{@type}..." %}` fired at compile time. Enum class
# methods are now attached per enum (`Enum.m` -> `Sig.m`, except `new`), so
# their macro bodies expand with `@type` = the receiver enum, as in Crystal.
# `::Sig.each {}` additionally covers the absolute-path refine site.
# Each case must print EXIT 7.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_class_method_inherit.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

HEAD_SRC='lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Enum
  def each(& : self ->)
    {% if @type.annotation(Flags) %}
      {% for member in @type.constants %}
        yield self.class.new({{@type.constant(member)}}), {{@type.constant(member)}}
      {% end %}
    {% else %}
      {% raise "Can'"'"'t iterate #{@type}: only Flags Enum can be iterated" %}
    {% end %}
  end

  def self.each(& : self ->)
    {% for member in @type.constants %}
      yield new({{@type.constant(member)}}), {{@type.constant(member)}}
    {% end %}
  end

  def self.member_count : Int32
    {{@type.constants.size}}
  end
end
'

# class-method each with a yielded block (Process-style Signal.each)
cat >"$WORK_DIR/each_sum.cr" <<CR
$HEAD_SRC
enum Sig
  A = 1
  B = 2
  C = 4
end

sum = 0
Sig.each do |s|
  sum += s.value
end
LibC.exit(sum)
CR

# absolute-path receiver with a brace block: the late PathNode refine kept
# the `::` prefix and fell to the instance `Sig#each` (macro raise)
cat >"$WORK_DIR/each_abs_brace.cr" <<CR
$HEAD_SRC
enum Sig
  A = 1
  B = 2
  C = 4
end

sum = 0
::Sig.each { |s| sum += s.value }
LibC.exit(sum)
CR

# @type expands per receiver enum: 3 + 2 + 2
cat >"$WORK_DIR/per_enum_type.cr" <<CR
$HEAD_SRC
enum Sig
  A
  B
  C
end

enum Two
  X
  Y
end

LibC.exit(Sig.member_count + Two.member_count + 2)
CR

for name in each_sum each_abs_brace per_enum_type; do
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
echo enum_class_method_inherit_repro_ok
