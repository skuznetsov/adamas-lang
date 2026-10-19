#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-crystal}"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: %s [original-crystal-bin]\n' "$0" >&2
  exit 2
fi
ORIGINAL="${1:-$ORIGINAL}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas_lexer_regression.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
CRYSTAL_CACHE_DIR="$WORK/cache" "$ROOT_DIR/scripts/run_safe.sh" "$ORIGINAL" 120 8192 \
  spec "$ROOT_DIR/spec/parser/lexer_operator_symbol_match_spec.cr" --error-trace
