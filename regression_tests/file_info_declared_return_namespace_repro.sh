#!/usr/bin/env bash
# File.info? must resolve Info? in File even when DWARF also defines Info.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="${RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
: "${CRYSTAL_PATH:?Set CRYSTAL_PATH to the external original Crystal stdlib}"
TMP_DIR="$(mktemp -d /tmp/file_info_declared_return_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
SRC="$TMP_DIR/probe.cr"
OUT="$TMP_DIR/probe"
cat > "$SRC" <<'CRYSTAL'
require "dir"
exit 11 unless Dir.exists?(".")
exit 12 if Dir.exists?("./absent")
if info = File.info?(".")
  exit 13 unless info.type.directory?
else
  exit 14
end
exit 15 unless File.info?("./absent").nil?
exit 0
CRYSTAL
"$RUN_SAFE" "$COMPILER" 60 2048 "$SRC" -o "$OUT" > "$TMP_DIR/compile.log" 2>&1 || { cat "$TMP_DIR/compile.log"; exit 1; }
(cd "$TMP_DIR" && "$RUN_SAFE" "$OUT" 5 512) > "$TMP_DIR/run.log" 2>&1 || { cat "$TMP_DIR/run.log"; exit 1; }
echo "file_info_declared_return_namespace_ok"
