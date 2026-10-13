#!/usr/bin/env bash
# Regression: a concrete argument passed through a union restriction with a
# module arm (`args : Enumerable(T)?`) must type the callee body by the
# concrete argument, as it already does for a bare module restriction.
# The call was bound to the declared-union body `f$Nil | Enumerable(Int32)`;
# `if args` then narrowed to the module type, `concat` selected
# `concat(other : Indexable)` and `insert_elements_at` re-dispatched on the
# module, reaching a bodyless `insert_elements_at$Indexable_Int32`.
# Wt-stdlib `Process.run(cmd, args)` hits this in `prepare_args`
# (`command_args.concat(args) if args` with `args : Enumerable(String)?`).
# Controls: bare module restriction, direct call, concrete nilable
# restriction, untyped param. Expected exit codes are from the host oracle.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nilable_module_restriction.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/base.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
module Enumerable(T)
end
module Indexable(T)
  include Enumerable(T)
end
struct Int32
  def +(other : Int32) : Int32
    self &+ other
  end
end
class Deq(T)
  include Indexable(T)
end
class Arr(T)
  include Indexable(T)
  @size = 0
  def initialize(@size : Int32)
  end
  def size : Int32
    @size
  end
  def concat(other : Indexable) : self
    insert_elements_at(other, @size)
    self
  end
  def concat(other : Enumerable) : self
    self
  end
  private def insert_elements_at(other : Arr, index : Int32) : Nil
    @size = @size + other.size + 10
  end
  private def insert_elements_at(other : Deq, index : Int32) : Nil
    @size = @size + 100
  end
  private def insert_elements_at(other, index : Int32) : Nil
    @size = @size + 1000
  end
end
CR

case_src() {
  case "$1" in
    nilable_module)
      printf '%s\n' 'def f(args : Enumerable(Int32)?)' '  a = Arr(Int32).new(1)' '  a.concat(args) if args' '  a.size' 'end' 'LibC.exit(f(Arr(Int32).new(2)))' ;;
    nilable_module_deq)
      printf '%s\n' 'def f(args : Enumerable(Int32)?)' '  a = Arr(Int32).new(1)' '  a.concat(args) if args' '  a.size' 'end' 'LibC.exit(f(Deq(Int32).new))' ;;
    nilable_module_nil)
      printf '%s\n' 'def f(args : Enumerable(Int32)?)' '  a = Arr(Int32).new(1)' '  a.concat(args) if args' '  a.size' 'end' 'LibC.exit(f(nil))' ;;
    bare_module)
      printf '%s\n' 'def f(args : Enumerable(Int32))' '  a = Arr(Int32).new(1)' '  a.concat(args)' '  a.size' 'end' 'LibC.exit(f(Arr(Int32).new(2)))' ;;
    direct)
      printf '%s\n' 'a = Arr(Int32).new(1)' 'a.concat(Arr(Int32).new(2))' 'LibC.exit(a.size)' ;;
    concrete_nilable)
      printf '%s\n' 'def f(args : Arr(Int32)?)' '  a = Arr(Int32).new(1)' '  a.concat(args) if args' '  a.size' 'end' 'LibC.exit(f(Arr(Int32).new(2)))' ;;
    untyped)
      printf '%s\n' 'def f(args)' '  a = Arr(Int32).new(1)' '  a.concat(args) if args' '  a.size' 'end' 'LibC.exit(f(Arr(Int32).new(2).as(Arr(Int32)?)))' ;;
  esac
}

for spec in nilable_module:13 nilable_module_deq:101 nilable_module_nil:1 bare_module:13 direct:13 concrete_nilable:13 untyped:13; do
  name="${spec%%:*}"
  want="${spec##*:}"
  { cat "$WORK_DIR/base.cr"; case_src "$name"; } >"$WORK_DIR/$name.cr"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    echo "case $name: compile failed" >&2
    tail -20 "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q "^\[EXIT: $want\]" "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT $want):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo nilable_module_restriction_specialization_repro_ok
