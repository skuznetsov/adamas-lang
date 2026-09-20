#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_CRYSTAL="${HOST_CRYSTAL:-crystal}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas-lsp-incremental-sync.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

link_args=()
if [[ -n "${CRYSTAL_LINK_FLAGS:-}" ]]; then
  link_args+=(--link-flags="$CRYSTAL_LINK_FLAGS")
elif [[ "$(uname -s)" == "Darwin" ]]; then
  link_args+=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

CRYSTAL_CACHE_DIR="$TMP_DIR/crystal-cache" "$HOST_CRYSTAL" build \
  "$ROOT_DIR/spec/lsp/did_change_integration_spec.cr" \
  -o "$TMP_DIR/did-change-spec" \
  --error-trace \
  "${link_args[@]}"

"$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/did-change-spec" 120 1536 --no-color
