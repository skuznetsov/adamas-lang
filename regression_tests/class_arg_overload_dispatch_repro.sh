#!/usr/bin/env bash
# Class-arg overload multi-dispatch (2026-06-12): a call whose argument is
# statically typed as a parent class must dispatch at runtime over the
# subclass-specific overloads, like original Crystal.
#
# V2 statically bound the exact parent-class overload: in stage2,
# `Frontend.node_literal(node)` (node : Node) always called the
# `node_literal(node : TypedNode) : Slice(UInt8)? = nil` fallback, so every
# named argument parsed with a NULL name slice. The B1b Slice(UInt8) identity
# unification turned that silent corruption into a startup segfault
# (NamedArgument#initialize memcpy from null).
#
# Fix: try_emit_class_arg_overload_dispatch in ast_to_hir.cr emits an is_a?
# chain over strict-subclass overloads (most specific first) with the static
# target as fallback. Module-owned class methods are reached through the
# receiverless call_virtual path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/class-arg-dispatch.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "usage: $0 <adamas-compiler>" >&2
  echo "missing executable compiler: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cat >"$SRC" <<'CR'
abstract class Node
end

class IdentifierNode < Node
  def initialize(@v : Int32)
  end

  def v : Int32
    @v
  end
end

class SpecialIdentifierNode < IdentifierNode
end

class OtherNode < Node
end

module M
  def self.lit(n : IdentifierNode) : Int32?
    n.v
  end

  def self.lit(n : Node) : Int32?
    nil
  end
end

# Case 1: runtime subtype with explicit overload must dispatch to it.
a : Node = IdentifierNode.new(42)
ra = M.lit(a)
exit 1 unless ra == 42

# Case 2: runtime subtype WITHOUT explicit overload must hit the fallback.
b : Node = OtherNode.new
rb = M.lit(b)
exit 2 unless rb.nil?

# Case 3: deeper runtime type dispatches to nearest ancestor overload.
c : Node = SpecialIdentifierNode.new(7)
rc = M.lit(c)
exit 3 unless rc == 7

# Case 4: static subtype call still binds directly.
d = IdentifierNode.new(5)
rd = M.lit(d)
exit 4 unless rd == 5

exit 0
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$SRC" --no-prelude -o "$OUT" >"$LOG" 2>&1 || {
  echo "compile failed" >&2
  cat "$LOG" >&2
  exit 2
}

RUN_LOG="$TMP_DIR/run.log"
code=0
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1 || code=$?
if [[ "$code" -eq 0 ]]; then
  echo "fixed: parent-class arg dispatches to subclass overloads at runtime"
  exit 0
fi

case "$code" in
  1) echo "open bug reproduced: subtype arg bound the parent-class fallback overload (case 1)" >&2 ;;
  2) echo "regression: fallback overload not reached for unmatched subtype (case 2)" >&2 ;;
  3) echo "regression: deep subtype missed nearest ancestor overload (case 3)" >&2 ;;
  4) echo "regression: static subtype call broken (case 4)" >&2 ;;
  *) echo "reducer binary failed (exit $code)" >&2; cat "$RUN_LOG" >&2 ;;
esac
exit 1
