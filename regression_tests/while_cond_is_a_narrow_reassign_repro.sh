#!/usr/bin/env bash
# `while x.is_a?(T) && ...` did not narrow `x` to T inside the loop body
# (lower_while applied only truthy narrowing). With `x` reassigned in the body
# (a loop-phi of type Nil | Node), `x.object` dispatched on the wide union;
# the Nil arm made the vdispatch void and a null struct ptr propagated
# (S2 crashed in arena_for_expr? on a null ExprId from the E2b not_nil! loop).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/while_cond_is_a_narrow_reassign_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
struct Id
  getter index : Int32
  def initialize(@index : Int32); end
end

abstract class Node; end
class Mem < Node
  getter object : Id
  getter member : String
  def initialize(@object : Id, @member : String); end
end
class Ident < Node
  getter name : String
  def initialize(@name : String); end
end
class Asg < Node
  getter value : Id
  def initialize(@value : Id); end
end

NODES = [] of Node

def node_for(id : Id) : Node?
  NODES[id.index]?
end

def infer(id : Id) : Int32
  id.index * 10
end

def collect(n : Node) : Int32
  if n.is_a?(Asg)
    value_expr = n.value
    value_node = node_for(value_expr)
    inferred = nil.as(Int32?)
    strip_nil = false
    while value_node.is_a?(Mem) && value_node.member == "not_nil!"
      value_expr = value_node.object
      value_node = node_for(value_expr)
      strip_nil = true
    end
    if value_node.is_a?(Ident)
      inferred = infer(value_expr) + 1
    elsif strip_nil
      inferred = infer(value_expr) + 2
    else
      inferred = infer(n.value) + 3
    end
    return inferred
  end
  0
end

NODES << Ident.new("x")               # 0
NODES << Mem.new(Id.new(0), "not_nil!") # 1
NODES << Asg.new(Id.new(1))           # 2
NODES << Asg.new(Id.new(0))           # 3
NODES << Mem.new(Id.new(5), "not_nil!") # 4
NODES << Asg.new(Id.new(3))           # 5 -> value is Asg (not ident)
NODES << Asg.new(Id.new(4))           # 6

def collect_plain(n : Node) : Int32
  return 0 unless n.is_a?(Asg)
  value_expr = n.value
  value_node = node_for(value_expr)
  hops = 0
  while value_node.is_a?(Mem)
    value_expr = value_node.object
    value_node = node_for(value_expr)
    hops += 1
  end
  value_expr.index * 10 + hops
end

STDERR.puts "c #{collect(NODES[2])}"
STDERR.puts "c #{collect(NODES[3])}"
STDERR.puts "c #{collect(NODES[5])}"
STDERR.puts "c #{collect(NODES[6])}"
STDERR.puts "p #{collect_plain(NODES[2])}"
STDERR.puts "p #{collect_plain(NODES[6])}"
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
printf 'c 1\nc 1\nc 33\nc 52\np 1\np 51\n' >"$WORK_DIR/expected"
grep -E '^[cp] ' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: while is_a? condition did not narrow the loop-phi var in the body" >&2
  exit 1
fi
echo "PASS: while is_a? condition narrows the loop-phi var in the body"
