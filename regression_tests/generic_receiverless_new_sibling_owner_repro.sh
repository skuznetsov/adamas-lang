#!/usr/bin/env bash
# A receiverless `new { ... }` inside a specialized generic `self.new` must
# stay on the concrete owner. The method-index owner filter used to keep
# bare-owner keys (Box.new$Float64$arity2, Box.new$block$arity1) next to the
# exact-owner keys; a bare key won the score tie and was then re-owned onto
# the first concrete sibling, so Box(UInt32, Int32).new called
# Box(Int64, Float64).new$Nil_block. This is the Hash(K, V).new(default)
# shape that miscompiled Hash counters in stage3.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-receiverless-new.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cat >"$SRC" <<'CR'
class Box(K, V)
  def initialize(block : (Box(K, V), K -> V)? = nil, *, initial_capacity = nil)
    @k = uninitialized K
    @d = uninitialized V
    @block = block
  end

  def self.new(initial_capacity = nil, &block : (Box(K, V), K -> V))
    new block, initial_capacity: initial_capacity
  end

  def self.new(default_value : V, initial_capacity = nil)
    new(initial_capacity: initial_capacity) { default_value }
  end

  def []=(k : K, v : V)
    @k = k
    @d = v
  end

  def get : V
    @d
  end
end

# The sibling instantiation must be discovered first.
def other
  b = Box(Int64, Float64).new(1.0)
  b[2_i64] = 3.0
  b.get
end

def elide
  h = Box(UInt32, Int32).new(0)
  h[1_u32] = 7
  h.get
end

other
elide
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  --no-prelude "$SRC" -o "$OUT" --emit hir >"$LOG" 2>&1
compile_rc=$?
set -e

echo "compiler: $COMPILER"
echo "compile_rc: $compile_rc"
if [[ $compile_rc -ne 0 || ! -f "$OUT.hir" ]]; then
  tail -80 "$LOG" >&2 || true
  echo "FAIL: receiverless generic new probe did not compile" >&2
  exit 1
fi

bad="$(awk '
  /^func / { fn = $0 }
  /call .*Box\(Int64, Float64\)/ && fn ~ /Box\(UInt32, Int32\)|@elide/ { print fn " :: " $0 }
' "$OUT.hir")"
if [[ -n "$bad" ]]; then
  echo "$bad" >&2
  echo "FAIL: Box(UInt32, Int32) constructor chain called the Box(Int64, Float64) sibling" >&2
  exit 1
fi

if ! grep -q 'call Box(UInt32, Int32).new\$Nil_block' "$OUT.hir"; then
  echo "FAIL: expected Box(UInt32, Int32).new\$Nil_block call not found" >&2
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$TMP_DIR/run.log" 2>&1
run_rc=$?
set -e
if [[ $run_rc -ne 0 ]]; then
  cat "$TMP_DIR/run.log" >&2
  echo "FAIL: linked probe did not run" >&2
  exit 1
fi

echo "PASS: receiverless generic new stays on the concrete owner"
