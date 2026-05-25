#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2-linux-stat-mtime.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

LOG="$TMP_DIR/build.log"

if ! crystal build "$ROOT_DIR/src/crystal_v2.cr" \
  -o "$TMP_DIR/crystal_v2_linux" \
  --error-trace \
  --cross-compile \
  --target x86_64-linux-gnu >"$LOG" 2>&1; then
  echo "p2_linux_cross_compile_stat_mtime_guard_failed: linux cross compile failed" >&2
  tail -160 "$LOG" >&2 || true
  exit 1
fi

echo "p2_linux_cross_compile_stat_mtime_guard_ok"
