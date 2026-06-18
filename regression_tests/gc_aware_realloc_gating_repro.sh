#!/usr/bin/env bash
# Regression test for the two-heap GC hazard fix (D) and its link-dependency gate.
#
# Fix (D): the atomic byte-buffer allocator family is redirected off the Boehm GC
# heap so no live String survives only on a heap Boehm cannot scan through libc
# containers (premature free -> String#byte_at SIGSEGV at s2b startup):
#   * GC.malloc_atomic -> __adamas_malloc64 (libc calloc; zeroes like Boehm)
#   * GC.realloc       -> __adamas_gc_aware_realloc (GC_base-aware: Boehm blocks
#                         realloc via GC_realloc, libc blocks via libc realloc)
# The scanned GC.malloc family (GMP, EventLoop arena) is left on Boehm.
#
# Link-dependency gate: @__adamas_gc_aware_realloc references @GC_base/@GC_realloc,
# which only resolve when libgc is linked. libgc is linked only when a GC method is
# reachable. The wrapper is therefore emitted ONLY when a reachable function calls
# GC_realloc (the same condition that links libgc). Emitting it unconditionally
# broke trivial GC-free programs (e.g. `x = 1`) with:
#   Undefined symbols: _GC_base, _GC_realloc
# which is exactly how stage2 (s2b) failed to link `x = 1` after the first cut of D.
#
# This script asserts both invariants against the stage1 compiler:
#   1. NEGATIVE GATE: a GC-free program (--no-prelude) emits NO wrapper and links
#      clean (no undefined _GC_base/_GC_realloc).
#   2. POSITIVE GATE + REDIRECT: a String-growing program emits the wrapper, makes
#      zero direct @GC_malloc_atomic calls (all redirected to libc), links, and
#      runs with the correct result.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gc_realloc_gate.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

fail() { echo "FAIL: $*"; echo "tmp_dir: $TMP_DIR (KEEP_TMP=1 to keep)"; exit 1; }

# ---------------------------------------------------------------------------
# 1. NEGATIVE GATE: GC-free no-prelude program must not emit the wrapper and
#    must link clean.
# ---------------------------------------------------------------------------
NEG_SRC="$TMP_DIR/neg.cr"
NEG_LL="$TMP_DIR/neg"
NEG_BIN="$TMP_DIR/neg.bin"
printf 'x = 1\n' >"$NEG_SRC"

"$COMPILER" --no-prelude "$NEG_SRC" -o "$NEG_LL" --emit llvm-ir >/dev/null 2>&1 \
  || fail "negative: --emit llvm-ir failed"
if grep -q "define ptr @__adamas_gc_aware_realloc" "$NEG_LL.ll"; then
  fail "negative: wrapper emitted for a GC-free program (gate did not fire)"
fi

set +e
"$COMPILER" --no-prelude "$NEG_SRC" -o "$NEG_BIN" >"$TMP_DIR/neg.link" 2>&1
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

# ---------------------------------------------------------------------------
# 2. POSITIVE GATE + REDIRECT: String-growing program emits the wrapper, makes
#    no direct GC_malloc_atomic calls, links, and runs correctly.
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
STDERR.flush
CR

"$COMPILER" "$POS_SRC" -o "$POS_LL" --emit llvm-ir >/dev/null 2>&1 \
  || fail "positive: --emit llvm-ir failed"
grep -q "define ptr @__adamas_gc_aware_realloc" "$POS_LL.ll" \
  || fail "positive: wrapper NOT emitted for a GC-using program (gate failed to fire)"
# All atomic byte-buffer allocations must be redirected to libc: zero *calls* to
# @GC_malloc_atomic (the bare declare is allowed; a 'call ... @GC_malloc_atomic' is not).
if grep -qE "call[^\n]*@GC_malloc_atomic\b" "$POS_LL.ll"; then
  fail "positive: residual GC_malloc_atomic call site (redirect to libc missed one)"
fi

set +e
"$COMPILER" "$POS_SRC" -o "$POS_BIN" >"$TMP_DIR/pos.link" 2>&1
pos_link_status=$?
set -e
if [[ $pos_link_status -ne 0 ]] || [[ ! -x "$POS_BIN" ]]; then
  echo "--- link output ---"; cat "$TMP_DIR/pos.link"
  fail "positive: GC-using program failed to link (status=$pos_link_status)"
fi

./scripts/run_safe.sh "$POS_BIN" 5 256 >"$RUN_OUT"
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r' | sed '/^$/d')"
expected="len=100"
if [[ "$stderr_text" != "$expected" ]]; then
  echo "--- run output ---"; cat "$RUN_OUT"
  fail "positive: unexpected runtime output (expected '$expected', got '$stderr_text')"
fi
echo "ok: GC-using program emits wrapper, redirects atomic family to libc, runs clean"

echo "PASS: gc_aware_realloc gating + redirect verified"
exit 0
