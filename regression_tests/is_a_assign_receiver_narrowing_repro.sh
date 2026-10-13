#!/usr/bin/env bash
# Regression: `(x = expr).is_a?(T) && x.m` did not narrow `x` to T.
# is_a_narrowing_targets only accepted a bare identifier receiver, so the
# right-hand side of `&&` (and the `if` body) dispatched `m` on the full
# `T | U | Nil` union with an unresolved return type. Original Crystal unwraps
# an assignment target (MainVisitor#get_expression_var). In S1 this miscompiled
# collect_local_assignment_types' `||=` widening chain, so S2 never widened
# `rescue_clauses ||= [...]` and S3 dropped every rescue clause.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/is_a_assign_receiver_narrowing_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/ia.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

abstract class Node
end

class Bin < Node
  def initialize(@op : Int32, @left : Int32)
  end

  def op : Int32
    @op
  end

  def left : Int32
    @left
  end
end

class Ident < Node
  def initialize(@name : Int32)
  end

  def name : Int32
    @name
  end
end

class Store
  def initialize
    @n0 = Ident.new(5).as(Node)
    @n1 = Bin.new(1, 0).as(Node)
  end

  def node(i : Int32) : Node?
    return @n0 if i == 0
    return @n1 if i == 1
    nil
  end
end

def chain(s : Store, i : Int32) : Int32
  if (b = s.node(i)).is_a?(Bin) && b.op == 1 &&
     (l = s.node(b.left)).is_a?(Ident) && l.name == 5
    return 1
  end
  0
end

def body(s : Store, i : Int32) : Int32
  if (b = s.node(i)).is_a?(Bin)
    return b.op + 10
  end
  0
end

s = Store.new
code = 0
code |= 1 unless chain(s, 1) == 1
code |= 2 unless chain(s, 0) == 0
code |= 4 unless chain(s, 7) == 0
code |= 8 unless body(s, 1) == 11
code |= 16 unless body(s, 0) == 0
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/ia.cr" --no-prelude -o "$WORK_DIR/ia" >"$WORK_DIR/ia.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/ia.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/ia" 5 512 >"$WORK_DIR/ia.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/ia.run.log"; then
  echo "FAIL: is_a? on an assignment receiver did not narrow the assigned local" >&2
  cat "$WORK_DIR/ia.run.log" >&2
  exit 1
fi
echo "PASS: (x = expr).is_a?(T) narrows x"
