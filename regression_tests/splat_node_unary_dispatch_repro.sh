#!/usr/bin/env bash
# Regression: SplatNode misdispatched as UnaryNode in lower_node fast dispatch.
#
# ast_to_hir.cr's lower_node has a fast `case kind` prefilter that recovers the
# concrete node class from Frontend.node_kind(node) and unsafe_as-casts before
# the type-safe `case node`. SplatNode has no dedicated NodeKind and shares
# NodeKind::Unary with UnaryNode (see ast.cr SplatNode#node_kind / the static
# self.node_kind(SplatNode) overload -- both return NodeKind::Unary). Their
# layouts differ:
#
#   SplatNode  = span + expr:ExprId                       (small allocation)
#   UnaryNode  = span + operator:Slice(16B) + operand:ExprId + operator_str:String
#
# UnaryNode#operand sits PAST the end of SplatNode's smaller heap allocation, so
# the unguarded `node.unsafe_as(UnaryNode)` in the `when NodeKind::Unary` branch
# read `operand` from adjacent heap (the source-text buffer) whenever the node
# was actually a SplatNode reaching lower_node via lower_expr. The bogus ExprId
# pulled from source bytes is the #4 producer; the original capture was a
# self-compile crash inside `Path.new$(Path | String)_Tuple()` (glob's splat
# parameter expansion) with caller frame:
#
#     ast_to_hir.cr:...    in 'lower_expr'      <- "ExprId out of bounds: <src bytes>"
#     ast_to_hir.cr:...    in 'lower_unary'     <- passed corrupt operand ExprId
#     ast_to_hir.cr:52229  in 'lower_node'      <- the NodeKind::Unary fast branch
#     ast_to_hir.cr:...    in 'lower_call'
#
# In the wild that path is layout/ASLR-gated (the over-read may land OOB ->
# raise, on a header-less String pointer -> segv, or benignly), so it only
# reproduced statistically. This reducer makes it DETERMINISTIC: an array
# literal splat `[*t, 9]` inside a directly-called method routes a SplatNode
# through the exact `when NodeKind::Unary` branch (verified: it is the only
# splat form here that hits the branch). On the pre-fix compiler the over-read
# crashes lowering every time (SIGSEGV, rc 139 -- with or without
# ADAMAS_EAGER_HIR); the fix compiles it cleanly.
#
# Fix: guard the cast -- `unless node.is_a?(SplatNode)` -- so only a real
# UnaryNode is unsafe_as-cast; SplatNode falls through to the type-safe
# `case node` arm that lowers it correctly via lower_expr(node.expr).
# See commit fix(hir): guard SplatNode in lower_node fast dispatch.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/splat_node_unary_dispatch.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
LOG="$TMP_DIR/compile.log"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

# `build` is called from top level so it is always lowered; `[*t, 9]` lowers the
# splat element through lower_expr -> lower_node -> the NodeKind::Unary fast
# branch. Self-contained, no prelude, no run -- we only assert lowering does not
# crash. (We never execute the binary: array-literal-splat expansion has a
# separate, unrelated open bug; this guard is scoped to the dispatch crash.)
cat >"$SRC" <<'CR'
def build(t)
  [*t, 9]
end

build({1, 2})
CR

set +e
"$COMPILER" --no-prelude "$SRC" --emit llvm-ir -o "$TMP_DIR/repro.bin" >"$LOG" 2>&1
status=$?
set -e

# Pre-fix: SIGSEGV during HIR lowering (rc 139, occasionally 134/11). Post-fix:
# clean (rc 0). Any non-zero status means the SplatNode/UnaryNode misdispatch
# (#4 producer) is reintroduced.
if [[ $status -ne 0 ]]; then
  echo "FAIL: compiler crashed lowering an array-literal splat (rc=$status)"
  echo "      SplatNode/UnaryNode misdispatch (#4 producer) reintroduced in lower_node."
  echo "compiler: $COMPILER"
  echo "tmp_dir: $TMP_DIR"
  echo "--- tail ---"
  tail -5 "$LOG"
  exit 1
fi

echo "ok (array-literal splat lowered without crash, rc=0)"
