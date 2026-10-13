#!/usr/bin/env bash
# `obj.class.name` / `.to_s` was lowered to the STATIC type name: a value typed
# as an abstract/virtual base always reported the base name. In the bootstrap,
# the class-arena fit check compares `member.class.name` with
# "Adamas::Compiler::Frontend::Node"; stage2 always saw "Node", rejected every
# class member, reparsed class bodies from snippets and lost macro-generated
# defs (e.g. `{% begin %} def self.new ... {% end %}`). Virtual receivers now
# read the i32 type_id header and use the backend type name table.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/runtime_class_name.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strcmp(a : UInt8*, b : UInt8*) : Int32
end
abstract class Node
end
class A < Node
end
class B < Node
end
class Leaf
end
module Wrap
  class Inner < Node
  end
end
def pick(i : Int32) : Node
  i == 0 ? A.new.as(Node) : B.new.as(Node)
end
def eq(s : String, t : String) : Bool
  LibC.strcmp(s, t) == 0
end
LibC.exit(1) unless eq(pick(0).class.name, "A")
LibC.exit(2) unless eq(pick(1).class.name, "B")
LibC.exit(3) if eq(pick(0).class.name, "Node")
LibC.exit(4) unless eq(Leaf.new.class.name, "Leaf")
n = Wrap::Inner.new.as(Node)
LibC.exit(5) unless eq(n.class.name, "Wrap::Inner")
LibC.exit(6) unless eq(pick(1).class.to_s, "B")
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo runtime_class_name_virtual_receiver_repro_ok
