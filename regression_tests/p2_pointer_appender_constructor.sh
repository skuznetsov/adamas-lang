#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <crystal-v2-compiler>" >&2
  exit 2
fi

COMPILER="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2_pointer_appender_constructor.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro_bin"

cat > "$SRC" <<'CR'
ptr = Pointer(UInt8).malloc(8)
app = ptr.appender
app << 1_u8
app << 2_u8

exit 10 unless app.size == 2_i64
exit 11 unless app.pointer.address - ptr.address == 2_u64
exit 12 unless app.to_slice.size == 2
exit 13 unless ptr[0] == 1_u8
exit 14 unless ptr[1] == 2_u8

puts "ok"
CR

"$ROOT/scripts/run_safe.sh" "$COMPILER" 120 4096 "$SRC" -o "$BIN"
"$ROOT/scripts/run_safe.sh" "$BIN" 5 512

echo "p2_pointer_appender_constructor_ok"
