#!/usr/bin/env bash
# Regression: `Pr.new(3, Ar(Int32).new(6))` into
# `initialize(cmd : Int32, args : En(Int32)? = nil)` where Ar includes
# Ix(T), which includes En(T). generate_allocator_overload specialized a
# declared union initializer param only for direct union members, so
# Ar(Int32) (a member only through the En module arm) collapsed to
# `En(Int32) | Nil`. The initializer and everything below it lost the
# concrete type and `concat(o : Ix)` -> `ins(o, i)` picked the untyped
# overload (EXIT 40 instead of 7). Original Crystal types the param as the
# argument type. Regular defs already did this (Bug A,
# union_module_arm_admits_concrete_call?); allocators now share it.
# Cases: direct `new` with a default arg, `self.run` -> `new` forwarding,
# the same without the default, plus nil/default-arg controls (EXIT 30) and
# a direct-member union control (EXIT 7). Expected exits checked against
# original Crystal --prelude=empty.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alloc_module_union_init.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/head.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
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
class Pr
  def r : Int32
    @r
  end
  def self.run(cmd : Int32, args : En(Int32)? = nil) : Int32
    new(cmd, args).r
  end
  def initialize(cmd : Int32, args : En(Int32)? = nil)
    @r = Sys.prep(cmd, args)
  end
end
class Pn
  def r : Int32
    @r
  end
  def self.run(cmd : Int32, args : En(Int32)? = nil) : Int32
    new(cmd, args).r
  end
  def initialize(cmd : Int32, args : En(Int32)?)
    @r = Sys.prep(cmd, args)
  end
end
class Pd
  def r : Int32
    @r
  end
  def initialize(cmd : Int32, args : Ar(Int32)? = nil)
    @r = Sys.prep(cmd, args)
  end
end
CR

run_case() {
  local name="$1" want="$2" main="$3"
  { cat "$WORK_DIR/head.cr"; echo "$main"; } >"$WORK_DIR/$name.cr"
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
}

run_case new_default 7 'LibC.exit(Pr.new(3, Ar(Int32).new(6)).r)'
run_case run_forward 7 'LibC.exit(Pr.run(3, Ar(Int32).new(6)))'
run_case run_forward_no_default 7 'LibC.exit(Pn.run(3, Ar(Int32).new(6)))'
run_case new_nil 30 'LibC.exit(Pr.new(3, nil).r)'
run_case new_omitted 30 'LibC.exit(Pr.new(3).r)'
run_case direct_member 7 'LibC.exit(Pd.new(3, Ar(Int32).new(6)).r)'
echo allocator_module_union_init_specialization_repro_ok
