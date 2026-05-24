#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <crystal-v2-compiler>" >&2
  exit 2
fi

COMPILER="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2_pointer_void_byte_stride.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro_bin"

cat > "$SRC" <<'CR'
base = Pointer(Void).malloc(32)
gap = (base + 3).address - base.address
exit 10 unless gap == 3_u64
exit 12 unless (base + 3) - base == 3_i64

src = Pointer(Void).malloc(32)
dst = base
src.as(UInt8*)[3] = 77_u8
dst.copy_from(src + 3, 1)
exit 11 unless dst.as(UInt8*)[0] == 77_u8

wide = Pointer(UInt32).malloc(2)
exit 13 unless (wide + 1).address - wide.address == 4_u64
exit 14 unless (wide + 1) - wide == 1_i64

puts "ok"
CR

"$ROOT/scripts/run_safe.sh" "$COMPILER" 120 4096 "$SRC" -o "$BIN"
"$ROOT/scripts/run_safe.sh" "$BIN" 5 512

echo "p2_pointer_void_byte_stride_ok"
