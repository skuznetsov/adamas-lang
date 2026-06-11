#!/usr/bin/env bash
# OPEN BUG (Step A proof, 2026-06-11): Slice(UInt8) ivar slot/access overlap.
#
# Ghost type identity: Slice(UInt8) is registered under two HIR TypeRef ids
# in one compile (early pre-registration ~id 156 + late generic instantiation
# ~id 891). HIR field_storage_size sizes the ivar slot via the stale view
# (slot = 8 bytes), while MIR lower_field_store_to_ptr lowers the write via
# the inline view (memcopy 16 bytes). A class
#
#   @before : Int64; @bytes : Slice(UInt8); @after : Int64
#
# lays out @bytes at +16 with an 8-byte slot and @after at +24; storing a
# slice memcpy's 16 bytes at +16, overwriting @after with the slice pointer.
# The read path also uses the 16-byte view, so @bytes itself stays
# self-consistent and the corruption only hits the NEIGHBOR field.
#
# Probe evidence (ADAMAS_LAYOUT_PROBE=1): hir field_storage_size slot=8 vs
# mir lower_field_store.memcopy access=16 for the same type name.
# See memory layout_decision_sidecar.md, divergence map Finding 1/2.
#
# EXPECTED TO FAIL until the ghost-identity / unified-layout fix (Step B+)
# lands. Asserts the correct behavior: both Int64 canaries intact.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slice_ivar_overlap.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
class Holder
  @before : Int64
  @bytes : Slice(UInt8)
  @after : Int64

  def initialize
    @before = 0x1111111111111111_i64
    @bytes = Slice(UInt8).empty
    @after = 0x2222222222222222_i64
  end

  def set_bytes(s : Slice(UInt8))
    @bytes = s
  end

  def bytes_size
    @bytes.size
  end

  def before_val
    @before
  end

  def after_val
    @after
  end
end

h = Holder.new
buf = Slice(UInt8).new(4) { |i| (i + 65).to_u8 }
h.set_bytes(buf)
STDERR.puts "size=#{h.bytes_size}"
if h.before_val == 0x1111111111111111_i64 && h.after_val == 0x2222222222222222_i64
  STDERR.puts "CANARIES_INTACT"
else
  STDERR.puts "CANARY_CLOBBERED before=#{h.before_val.to_s(16)} after=#{h.after_val.to_s(16)}"
end
STDERR.flush
CR

set +e
"$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr ---"
  cat "$COMPILE_ERR"
  echo "--- stdout ---"
  cat "$COMPILE_OUT"
  exit 2
fi

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT"
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

if grep -q 'CANARIES_INTACT' <<<"$stderr_text" && grep -q 'size=4' <<<"$stderr_text"; then
  echo "fixed: Slice(UInt8) ivar slot matches its store/read access size"
  exit 0
fi

echo "open bug reproduced: Slice(UInt8) 8-byte slot receives 16-byte memcopy, neighbor ivar clobbered"
exit 1
