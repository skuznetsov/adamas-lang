#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [crystal-compiler]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRYSTAL_BIN="${1:-crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lower_main_arena_restore.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
CRYSTAL_CACHE_DIR="$WORK_DIR/cache" \
  scripts/run_safe.sh "$CRYSTAL_BIN" 180 7000 \
    spec spec/hir/ast_to_hir_spec.cr --error-trace \
    --example "restores the caller arena before later function lowering"

echo "not reproduced: lower_main restores its caller arena"
