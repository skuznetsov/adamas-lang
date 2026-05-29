#!/usr/bin/env bash
# Regression: generated concrete getters must materialize before inherited
# abstract-method lookup. Otherwise a call through an abstract receiver can
# resolve back to the abstract owner and LLVM emits a STUB CALLED abort.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_abstract_getter_vdispatch_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/compile.log"
LL="$OUT.ll"

cat >"$SRC" <<'CR'
class Object
end

class Reference < Object
end

struct Span
  @start : Int32

  def initialize(@start)
  end

  def start
    @start
  end
end

abstract class Node < Reference
  abstract def span : Span
end

class LiteralNode < Node
  getter span : Span

  def initialize(@span)
  end
end

def maybe_node(node : Node, enabled : Bool) : Node?
  return nil unless enabled
  node
end

def node_span(node : Node, enabled : Bool) : Span
  narrowed = maybe_node(node, enabled)
  return Span.new(0) unless narrowed
  narrowed.span
end

node_span(LiteralNode.new(Span.new(7)).as(Node), true).start
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 \
  "$SRC" --no-prelude --emit llvm-ir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$LL" ]]; then
  echo "p2_abstract_getter_vdispatch_failed: missing LLVM IR artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

if grep -q 'STUB CALLED: Node$Hspan' "$LL"; then
  echo "p2_abstract_getter_vdispatch_failed: abstract Node#span stub emitted" >&2
  grep -n 'STUB CALLED: Node$Hspan' "$LL" >&2
  exit 1
fi

if ! grep -q 'define ptr @LiteralNode$Hspan' "$LL"; then
  echo "p2_abstract_getter_vdispatch_failed: concrete getter was not materialized" >&2
  exit 1
fi

if ! grep -q 'call ptr @__vdispatch__Node$Hspan' "$LL"; then
  echo "p2_abstract_getter_vdispatch_failed: abstract receiver did not lower through vdispatch" >&2
  exit 1
fi

echo "p2_abstract_getter_vdispatch_no_prelude_ok"
