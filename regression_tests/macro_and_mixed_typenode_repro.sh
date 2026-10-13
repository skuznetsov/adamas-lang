#!/usr/bin/env bash
# Regression: an in-def `{% if %}` the HIR evaluator cannot fold (it does not
# know `T.union?`) falls back to the MacroExpander value path. There a bare
# type path (`Bool`, `Base`) evaluated to MacroId("Bool") instead of a TypeNode,
# so `T == Bool` compared TypeNode with MacroId (always false), and TypeNode
# `<`/`>`/`union?` returned nil. Stdlib `Atomic(T)#initialize`
# (`!T.union? && (T == Bool || T == Char || T < Int::Primitive || T < Enum)`)
# therefore raised "Can only create Atomic with ..." for Atomic(Bool).
# Positive file must print EXIT 7; the Float64 file must fail to compile with
# the macro raise message.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_and_mixed_typenode.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

HEAD_SRC='lib LibC
  fun exit(status : Int32) : NoReturn
end

# Same nested-alias shape as stdlib int.cr (`Primitive = Signed | Unsigned`).
# `Enum` is deliberately NOT reopened: it is a builtin Program type.
struct Int
  alias Signed = Int8 | Int16 | Int32 | Int64 | Int128
  alias Unsigned = UInt8 | UInt16 | UInt32 | UInt64 | UInt128
  alias Primitive = Signed | Unsigned
end

class Atom(T)
  def initialize(@value : T)
    {% if !T.union? && (T == Bool || T == Char || T < Int::Primitive || T < Enum) %}
    {% else %}
      {% raise "Can only create Atom with primitive integer types, Bool, Char or Enum, not #{T}" %}
    {% end %}
  end
end
'

cat >"$WORK_DIR/pos.cr" <<CR
$HEAD_SRC
enum Color
  Red
  Green
end

class Base
end

class Sub < Base
end

class Mixed(T)
  def initialize(@value : T)
    {% if !T.union? && T == Bool %}
    {% else %}
      {% raise "mixed: #{T}" %}
    {% end %}
  end
end

class Lt(T)
  def initialize(@value : T)
    {% if !T.union? && T < Base %}
    {% else %}
      {% raise "lt: #{T}" %}
    {% end %}
  end
end

class Gt(T)
  def initialize(@value : T)
    {% if !T.union? && Base > T %}
    {% else %}
      {% raise "gt: #{T}" %}
    {% end %}
  end
end

class Un(T)
  def initialize(@value : T)
    {% if T.union? %}
    {% else %}
      {% raise "union: #{T}" %}
    {% end %}
  end
end

class NotUnion(T)
  def initialize(@value : T)
    {% if T.union? %}
      {% raise "not-union: #{T}" %}
    {% end %}
  end
end

Atom(Bool).new(true)
Atom(Int32).new(1)
Atom(Char).new('c')
Atom(Color).new(Color::Green)
Mixed(Bool).new(false)
Lt(Sub).new(Sub.new)
Gt(Sub).new(Sub.new)
Un(Int32 | Bool).new(1)
NotUnion(Int32).new(1)
LibC.exit(7)
CR

cat >"$WORK_DIR/neg_float.cr" <<CR
$HEAD_SRC
Atom(Float64).new(1.0)
LibC.exit(7)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/pos.cr" --no-prelude -o "$WORK_DIR/pos" >"$WORK_DIR/pos.build.log" 2>&1; then
  echo "case pos: compile failed" >&2
  tail -20 "$WORK_DIR/pos.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/pos" 5 512 >"$WORK_DIR/pos.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 7\]' "$WORK_DIR/pos.run.log"; then
  echo "case pos failed (want EXIT 7):" >&2
  grep -E '^\[EXIT' "$WORK_DIR/pos.run.log" >&2 || cat "$WORK_DIR/pos.run.log" >&2
  exit 1
fi

if "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/neg_float.cr" --no-prelude -o "$WORK_DIR/neg_float" >"$WORK_DIR/neg.build.log" 2>&1 &&
   ! grep -q 'Can only create Atom' "$WORK_DIR/neg.build.log"; then
  echo "case neg_float: compiled without the macro raise" >&2
  exit 1
fi
if ! grep -q 'Can only create Atom with primitive integer types, Bool, Char or Enum, not Float64' "$WORK_DIR/neg.build.log"; then
  echo "case neg_float: missing macro raise message" >&2
  tail -20 "$WORK_DIR/neg.build.log" >&2
  exit 1
fi
echo macro_and_mixed_typenode_repro_ok
