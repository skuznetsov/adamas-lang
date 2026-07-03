#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <crystal-v2-compiler>" >&2
  exit 2
fi

COMPILER="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_io_memory_materialization.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro_bin"
RUN_LOG="$TMP_DIR/run.log"

cat > "$SRC" <<'CR'
io = IO::Memory.new
io << "abc"
io.write("-def".to_slice)

str = io.to_s
exit 10 unless str == "abc-def"
exit 11 unless str.bytesize == 7

slice = io.to_slice
exit 12 unless slice.size == 7
exit 13 unless slice[0] == 97_u8
exit 14 unless String.new(slice) == "abc-def"
exit 15 unless String.new(io.buffer, io.bytesize) == "abc-def"

sink = IO::Memory.new
io.to_s(sink)
exit 16 unless sink.to_s == "abc-def"

big = IO::Memory.new
chunk = "0123456789abcdef\n"
repeat = 120_000
repeat.times do
  big << chunk
end

expected = chunk.bytesize * repeat
big_str = big.to_s
exit 20 unless big_str.bytesize == expected
exit 21 unless big.to_slice.size == expected
exit 22 unless String.new(big.buffer, big.bytesize).bytesize == expected

puts "io_memory_materialization_ok"
CR

"$ROOT/scripts/run_safe.sh" "$COMPILER" 180 4096 "$SRC" -o "$BIN"
"$ROOT/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1

if ! grep -q "io_memory_materialization_ok" "$RUN_LOG"; then
  echo "io_memory_final_materialization_repro_failed: unexpected output" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "io_memory_final_materialization_repro_ok"
