#!/usr/bin/env bash
# Root-qualified generic use must not invalidate an ordinary Hash literal.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="${RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
TMP_DIR="$(mktemp -d /tmp/hash_global_qualification_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

for order in literal-first qualified-first; do
  SRC="$TMP_DIR/$order.cr"
  OUT="$TMP_DIR/$order"
  cat > "$SRC" <<'CRYSTAL'
class Hash(K, V)
  @indices_bytesize : UInt8 = 1_u8
  @tail : UInt64 = 0_u64
  def initialize
  end
  def tail : UInt64
    @tail
  end
  def indices_width : UInt8
    @indices_bytesize
  end
end
CRYSTAL
  if [[ "$order" == literal-first ]]; then
    printf '%s\n' 'h = {} of Int32 => Int32' 'qualified = ::Hash(Int32, Int32).new' >> "$SRC"
  else
    printf '%s\n' 'qualified = ::Hash(Int32, Int32).new' 'h = {} of Int32 => Int32' >> "$SRC"
  fi
  cat >> "$SRC" <<'CRYSTAL'
exit 11 unless h.tail == 0_u64
exit 12 unless h.indices_width == 1_u8
exit 13 unless qualified.tail == 0_u64
exit 0
CRYSTAL
  "$RUN_SAFE" "$COMPILER" 30 2048 "$SRC" --no-prelude -o "$OUT" > "$OUT.compile.log" 2>&1 || { cat "$OUT.compile.log"; exit 1; }
  "$RUN_SAFE" "$OUT" 5 512 > "$OUT.run.log" 2>&1 || { cat "$OUT.run.log"; exit 1; }
done
echo "hash_literal_global_qualification_ok"
