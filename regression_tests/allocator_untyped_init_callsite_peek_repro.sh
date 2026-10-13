#!/usr/bin/env bash
# Regression: `Foo.new(arg)` into an untyped `initialize(args)`.
# lower_function_if_needed_impl's `Owner.method` branch popped the pending
# callsite arg types while probing the unbound-instance-method and
# type-literal class-method wrappers. When neither wrapper applied, control
# fell through to the class-allocator path, which then saw no callsite and
# built a VOID base allocator `Qv#initialize$arity1(args: Void)`: a bodyless
# target compile error (qv) or the untyped `ins` overload (q -> 40, or 30
# when `args` collapsed to Nil). Fix: peek the callsite, pop only when a
# wrapper is created. Each case prints EXIT 7 (checked against original
# Crystal --prelude=empty). untyped_forward_to_module_union is the
# qualifier (pre-fix EXIT 30); the `@r : Int32` cases are controls, since
# the unannotated `@r = args.n` form (pre-fix bodyless-target error) is
# rejected by original Crystal.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alloc_callsite_peek.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/head.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Bx
  def initialize(@n : Int32)
  end
  def n : Int32
    @n
  end
end
CR

cat >"$WORK_DIR/untyped_only.cr" <<'CR'
class Qv
  @r : Int32
  def initialize(args)
    @r = args.n
  end
  def r : Int32
    @r
  end
end
LibC.exit(Qv.new(Bx.new(7)).r)
CR

cat >"$WORK_DIR/typed_plus_untyped.cr" <<'CR'
class Qc
  @r : Int32
  def initialize(x : Int32, args)
    @r = args.n &+ x
  end
  def r : Int32
    @r
  end
end
LibC.exit(Qc.new(2, Bx.new(5)).r)
CR

cat >"$WORK_DIR/untyped_forward_to_module_union.cr" <<'CR'
module En(T)
end
module Ix(T)
  include En(T)
end
class Ar(T)
  include Ix(T)
  def initialize(@n : Int32)
  end
  def n : Int32
    @n
  end
  def concat(o : Ix) : Int32
    ins(o, 1)
  end
  def concat(o : En) : Int32
    50
  end
  private def ins(o : Ar, i : Int32) : Int32
    o.n &+ i
  end
  private def ins(o, i : Int32) : Int32
    40
  end
end
module Sys
  def self.prep(cmd : Int32, args : En(Int32)?) : Int32
    a = Ar(Int32).new(cmd)
    if args
      a.concat(args)
    else
      30
    end
  end
end
class Q
  def initialize(cmd : Int32, args)
    @r = Sys.prep(cmd, args)
  end
  def r : Int32
    @r
  end
end
LibC.exit(Q.new(3, Ar(Int32).new(6)).r)
CR

for name in untyped_only typed_plus_untyped untyped_forward_to_module_union; do
  cat "$WORK_DIR/head.cr" "$WORK_DIR/$name.cr" >"$WORK_DIR/$name.full.cr"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.full.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
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
echo allocator_untyped_init_callsite_peek_repro_ok
