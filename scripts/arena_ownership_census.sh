#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SAMPLES="${SAMPLES:-12}"

if [[ ! -f "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr" ]]; then
  echo "usage: $0 [repo-root]" >&2
  echo "error: $ROOT_DIR does not look like the Adamas repo root" >&2
  exit 2
fi

cd "$ROOT_DIR"

AST_TO_HIR="src/compiler/hir/ast_to_hir.cr"

section() {
  printf '\n## %s\n' "$1"
}

sample_rg() {
  local pattern="$1"
  local file="$2"
  local count

  count="$({ rg -n --no-heading -e "$pattern" "$file" 2>/dev/null || true; } | wc -l | tr -d ' ')"
  echo "hits: $count"
  if [[ "$count" != "0" ]]; then
    { rg -n --no-heading -e "$pattern" "$file" 2>/dev/null || true; } | head -n "$SAMPLES"
  fi
}

sample_prefixed() {
  local pattern="$1"
  local file="$2"
  local count

  count="$({ grep -E "$pattern" "$file" 2>/dev/null || true; } | wc -l | tr -d ' ')"
  echo "hits: $count"
  if [[ "$count" != "0" ]]; then
    { grep -E "$pattern" "$file" 2>/dev/null || true; } | head -n "$SAMPLES"
  fi
}

tmp_dir="$(mktemp -d "$ROOT_DIR/tmp/arena-ownership-census.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

lower_call_file="$tmp_dir/lower_call.cr"
awk '
  /^    private def lower_call\(/ { in_lower_call = 1 }
  in_lower_call && /^    private def / && !/^    private def lower_call\(/ { exit }
  in_lower_call { printf "%d:%s\n", NR, $0 }
' "$AST_TO_HIR" > "$lower_call_file"

echo "# Arena Ownership Census"
echo "repo: $ROOT_DIR"
echo "samples_per_section: $SAMPLES"
echo "note: static grep only; this is an owner-map input, not liveness or safety proof"

section "AstNodeIdentity / owner helpers"
echo "files: $AST_TO_HIR"
echo "pattern: with_arena|arena_for_expr|node_for_expr|node_for_call_expr|@main_arenas|@inline_arenas|source_for_arena"
sample_rg "with_arena|arena_for_expr|node_for_expr|node_for_call_expr|@main_arenas|@inline_arenas|source_for_arena" "$AST_TO_HIR"

section "Raw arena reads / global"
echo "files: $AST_TO_HIR"
echo 'pattern: @arena\['
sample_rg "@arena\\[" "$AST_TO_HIR"

section "Raw arena reads / lower_call"
echo "files: $AST_TO_HIR extracted lower_call"
echo 'pattern: @arena\['
sample_prefixed "@arena\\[" "$lower_call_file"

section "Containment heuristics"
echo "files: $AST_TO_HIR"
echo "pattern: expr_id.index <|index < @arena.size|index < .*\\.size|arena.size"
sample_rg "expr_id\\.index <|index < @arena\\.size|index < .*\\.size|arena\\.size" "$AST_TO_HIR"

section "Existing debug gates around arena ownership"
echo "files: $AST_TO_HIR"
echo "pattern: DEBUG_.*ARENA|ADAMAS_.*ARENA|INFER_NODE|LOWER_CALL"
sample_rg "DEBUG_.*ARENA|ADAMAS_.*ARENA|INFER_NODE|LOWER_CALL" "$AST_TO_HIR"
