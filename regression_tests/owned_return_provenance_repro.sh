#!/usr/bin/env bash
# Mixed owned/borrowed return paths must not authorize caller ARC cleanup.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_CRYSTAL="${HOST_CRYSTAL:-crystal}"
RUN_SAFE="${RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
TMP_DIR="$(mktemp -d /tmp/owned_return_provenance_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
"$RUN_SAFE" "$HOST_CRYSTAL" 120 4096 build \
  "$ROOT_DIR/spec/mir/owned_return_provenance_spec.cr" -o "$TMP_DIR/spec" \
  > "$TMP_DIR/build.log" 2>&1 || { cat "$TMP_DIR/build.log"; exit 1; }
"$RUN_SAFE" "$TMP_DIR/spec" 15 512 \
  > "$TMP_DIR/run.log" 2>&1 || { cat "$TMP_DIR/run.log"; exit 1; }
cat "$TMP_DIR/run.log"
echo "owned_return_provenance_ok"
