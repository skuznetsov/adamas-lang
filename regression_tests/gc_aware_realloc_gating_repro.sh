#!/usr/bin/env bash
# Managed-heap regression for realloc routing and the collector link gate.
# No-prelude/no-GC modules must retain native allocation without GC references.
# Full-prelude String growth must keep atomic bytes collector-owned, emit the
# GC-base-aware realloc wrapper, and preserve the resulting String contents.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gc_realloc_gate.XXXXXX")"
cleanup() { if [[ "$KEEP_TMP" != "1" ]]; then rm -rf "$TMP_DIR"; fi; }
trap cleanup EXIT

fail() { echo "FAIL: $*"; echo "tmp_dir: $TMP_DIR (KEEP_TMP=1 to keep)"; exit 1; }
run_compiler() {
  local label="$1"
  shift
  RUN_SAFE_RESOURCE_FILE="$TMP_DIR/$label.resources" \
    "$SAFE_RUNNER" "$COMPILER" 240 6144 "$@"
}

# ---------------------------------------------------------------------------
# 1. NEGATIVE GATE: GC-free no-prelude program must not emit the wrapper and
#    must link clean.
# ---------------------------------------------------------------------------
NEG_SRC="$TMP_DIR/neg.cr"
NEG_LL="$TMP_DIR/neg"
NEG_BIN="$TMP_DIR/neg.bin"
printf 'x = 1\n' >"$NEG_SRC"

run_compiler neg_ir --no-prelude "$NEG_SRC" -o "$NEG_LL" --emit llvm-ir >"$TMP_DIR/neg.ir.log" 2>&1 \
  || fail "negative: --emit llvm-ir failed"
if grep -q "define ptr @__adamas_gc_aware_realloc" "$NEG_LL.ll"; then
  fail "negative: wrapper emitted for a GC-free program (gate did not fire)"
fi

set +e
run_compiler neg_link --no-prelude "$NEG_SRC" -o "$NEG_BIN" >"$TMP_DIR/neg.link" 2>&1
neg_link_status=$?
set -e
if [[ $neg_link_status -ne 0 ]] || [[ ! -x "$NEG_BIN" ]]; then
  echo "--- link output ---"; cat "$TMP_DIR/neg.link"
  fail "negative: GC-free program failed to link (status=$neg_link_status)"
fi
if grep -qE "Undefined symbols|_GC_base|_GC_realloc" "$TMP_DIR/neg.link"; then
  echo "--- link output ---"; cat "$TMP_DIR/neg.link"
  fail "negative: undefined GC symbols leaked into link"
fi
echo "ok: GC-free program emits no wrapper and links clean"

run_compiler no_gc_ir --no-prelude --no-gc "$NEG_SRC" -o "$TMP_DIR/no_gc" --emit llvm-ir >"$TMP_DIR/no_gc.ir.log" 2>&1 \
  || fail "no-GC: --emit llvm-ir failed"
if grep -qE 'call .*@GC_(malloc|malloc_atomic|base|realloc|free)' "$TMP_DIR/no_gc.ll"; then
  fail "no-GC: collector calls leaked into native allocation helpers"
fi
run_compiler no_gc_link --no-prelude --no-gc "$NEG_SRC" -o "$TMP_DIR/no_gc.bin" >"$TMP_DIR/no_gc.link" 2>&1 \
  || fail "no-GC: native program failed to link"
RUN_SAFE_RESOURCE_FILE="$TMP_DIR/no_gc.run.resources" \
  "$SAFE_RUNNER" "$TMP_DIR/no_gc.bin" 5 256 >"$TMP_DIR/no_gc.run" 2>&1 \
  || fail "no-GC: native program failed to run"
echo "ok: explicit no-GC program retains native helpers and runs clean"

# ---------------------------------------------------------------------------
# 2. POSITIVE GATE: String-growing storage stays atomic and collector-owned.
# ---------------------------------------------------------------------------
POS_SRC="$TMP_DIR/pos.cr"
POS_LL="$TMP_DIR/pos"
POS_BIN="$TMP_DIR/pos.bin"
RUN_OUT="$TMP_DIR/pos.run"
cat >"$POS_SRC" <<'CR'
s = String.build do |io|
  i = 0
  while i < 50
    io << "ab"
    i += 1
  end
end
STDERR.puts "len=#{s.size}"
STDERR.puts "managed=#{GC.is_heap_ptr(s.to_unsafe.as(Void*)) ? 1 : 0}"
STDERR.flush
CR

run_compiler pos_ir "$POS_SRC" -o "$POS_LL" --emit llvm-ir >"$TMP_DIR/pos.ir.log" 2>&1 \
  || fail "positive: --emit llvm-ir failed"
grep -q "define ptr @__adamas_gc_aware_realloc" "$POS_LL.ll" \
  || fail "positive: wrapper NOT emitted for a GC-using program (gate failed to fire)"
grep -qE 'call .*@GC_malloc_atomic\(' "$POS_LL.ll" \
  || fail "positive: managed atomic allocator did not call Boehm"

set +e
run_compiler pos_link "$POS_SRC" -o "$POS_BIN" >"$TMP_DIR/pos.link" 2>&1
pos_link_status=$?
set -e
if [[ $pos_link_status -ne 0 ]] || [[ ! -x "$POS_BIN" ]]; then
  echo "--- link output ---"; cat "$TMP_DIR/pos.link"
  fail "positive: GC-using program failed to link (status=$pos_link_status)"
fi

RUN_SAFE_RESOURCE_FILE="$TMP_DIR/pos.run.resources" \
  "$SAFE_RUNNER" "$POS_BIN" 5 256 >"$RUN_OUT" 2>&1
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r' | sed '/^$/d')"
expected=$'len=100\nmanaged=1'
if [[ "$stderr_text" != "$expected" ]]; then
  echo "--- run output ---"; cat "$RUN_OUT"
  fail "positive: unexpected runtime output (expected '$expected', got '$stderr_text')"
fi
echo "ok: GC-using program emits wrapper, retains managed atomic storage, runs clean"

echo "PASS: gc_aware_realloc native/managed gates verified"
exit 0
