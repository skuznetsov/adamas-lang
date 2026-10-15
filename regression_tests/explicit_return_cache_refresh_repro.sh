#!/usr/bin/env bash
# Late nested declarations refresh only their own lexical return cache entries.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SPEC_ROOT="${ADAMAS_SPEC_ROOT:-$ROOT_DIR}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/explicit-return-cache.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$SPEC_ROOT"
env CRYSTAL_CACHE_DIR="$WORK_DIR/cache" \
  "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL" 180 12288 \
  spec --no-color --link-flags=-fuse-ld=/usr/bin/ld \
  spec/hir/explicit_return_cache_refresh_spec.cr
printf 'PASS: lexical return cache refresh preserves sibling and generic ownership\n'
