#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HIR_SOURCE="$ROOT_DIR/src/compiler/hir/hir.cr"
LOWERING_SOURCE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"

violations="$(
  rg -n \
    '@function_lowering_states\[[^]]+\][[:space:]]*=|@function_lowering_states\.delete|@pending_function_queue[[:space:]]*<<|@pending_function_queue\.clear|@function_defs\[[^]]+\][[:space:]]*=|@function_types\[[^]]+\][[:space:]]*=|@function_types\.delete|(@instructions|\.instructions)\[[^]]+\][[:space:]]*=|(@instructions|\.instructions)\.insert|\.method_name[[:space:]]*=[^=]|\.args[[:space:]]*<<' \
    "$HIR_SOURCE" \
    "$LOWERING_SOURCE" |
    rg -v 'missing-revision-owner' || true
)"

if [ -n "$violations" ]; then
  echo "missing-call revision ownership violations:"
  echo "$violations"
  exit 1
fi

echo "missing-call revision ownership: PASS"
