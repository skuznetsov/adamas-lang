#!/usr/bin/env bash
# A zero-arg call on an abstract base (`node.span` with `node : Node`) must
# dispatch virtually to the subclasses' `getter span` accessors. The bare
# inherited-nilary lookup bound `ANode#span` to the abstract `Node#span`
# declaration, so vdispatch was dropped and the abstract stub aborted.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/abstract_getter_vdispatch.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/t.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

abstract class Node
  abstract def span : Int32
end

class ANode < Node
  getter span : Int32
  def initialize(@span : Int32)
  end
end

class BNode < Node
  getter span : Int32
  def initialize(@span : Int32)
  end
end

def pick(i : Int32) : Node
  i == 0 ? ANode.new(1) : BNode.new(7)
end

def reg(node : Node) : Int32
  node.span
end

r = reg(pick(1)) + reg(pick(0)) * 100
LibC.exit(r == 107 ? 3 : 1)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
    "$WORK_DIR/t.cr" --no-prelude -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/run.log"; then
  echo "want EXIT 3" >&2
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo PASS
