#!/usr/bin/env bash
# Regression: builtin hierarchy in no-prelude programs.
# Original Crystal always has `Struct < Value < Object` and
# `Int32 < Int < Number < Value`, even when the source never reopens those
# types. get_parent_chain walked only registered ClassInfo/class_parents, so
# an undeclared `Struct` (or a primitive without ClassInfo) ended the parent
# walk and `struct Value` methods were unreachable: the call lowered to a
# bodyless stub (EXIT 134) or failed receiver repair at compile time.
# Cases: struct -> Value, generic struct -> Value, Int32 -> Value,
# Value#==(other) fallback from a struct, and a class -> Object control.
# Each prints EXIT 7.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/builtin_hierarchy.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

HEAD='lib LibC
  fun exit(code : Int32) : NoReturn
end
struct Value
  def vv : Int32
    7
  end

  def ==(other)
    false
  end
end
class Object
  def oo : Int32
    7
  end
end'

printf '%s\nstruct Pt\n  def initialize(@a : Int32)\n  end\nend\nLibC.exit(Pt.new(1).vv)\n' "$HEAD" >"$WORK_DIR/struct_value.cr"
printf '%s\nstruct Pt(T)\n  def initialize(@a : T)\n  end\nend\nLibC.exit(Pt(UInt8).new(1_u8).vv)\n' "$HEAD" >"$WORK_DIR/generic_struct_value.cr"
printf '%s\nLibC.exit(3.vv)\n' "$HEAD" >"$WORK_DIR/int_value.cr"
printf '%s\nstruct Pt\n  def initialize(@a : Int32)\n  end\nend\nLibC.exit((Pt.new(1) == 3) ? 40 : 7)\n' "$HEAD" >"$WORK_DIR/struct_value_eq.cr"
printf '%s\nclass Foo\nend\nLibC.exit(Foo.new.oo)\n' "$HEAD" >"$WORK_DIR/class_object.cr"

for name in struct_value generic_struct_value int_value struct_value_eq class_object; do
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
echo builtin_hierarchy_parent_chain_repro_ok
