#!/usr/bin/env bash
# E-R11 — the s2b reproducer for the ARC-owned-String (E) work (SDD §8).
#
# Invariant: the stage1 compiler builds + cleanly runs the programs that
# exercise the dynamic-String producer surface, and (opt-in) self-builds
# `src/adamas.cr` cleanly. This is the "original crash, under freeable strings"
# guard: the #1 s2b startup crash (String#byte_at SIGSEGV) was a two-heap GC
# hazard fixed by D (`e635fbc4`, leak-to-exit). Once P2 flips the ARC-owned-String
# ABI and starts freeing dynamic Strings, this must STILL build+run clean.
#
# Machine-load note: this box is shared with heavy ML sessions. The full s2b
# self-build (`src/adamas.cr`, ~minutes, multi-GB) is OPT-IN via ADAMAS_ER11_FULL=1.
# By default only the bounded proxies run (seconds, <256MB):
#   1. `x = 1`            — GC-free; the exact program whose link D's first cut broke
#                           (undefined _GC_base/_GC_realloc). Must link + run exit 0.
#   2. string-churn mix   — hash + array + builder + interpolation + concat + slice,
#                           the dynamic-String producer surface (E-R0 census). Must
#                           build + run clean with correct output.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"
ER11_FULL="${ADAMAS_ER11_FULL:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arc_er11.XXXXXX")"
cleanup() { [[ "$KEEP_TMP" != "1" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

fail() { echo "FAIL: $*"; echo "tmp_dir: $TMP_DIR (KEEP_TMP=1 to keep)"; exit 1; }

run_clean() {
  # run_clean <bin> <expected-stderr-or-empty>; asserts exit 0 (+ optional output)
  local bin="$1" expect="${2:-}"
  local out="$TMP_DIR/$(basename "$bin").run"
  set +e
  ./scripts/run_safe.sh "$bin" 10 256 >"$out"
  set -e
  if ! grep -q '^\[EXIT: 0\]' "$out"; then
    echo "--- run output ---"; cat "$out"
    fail "$(basename "$bin"): non-zero exit (expected clean exit 0)"
  fi
  if [[ -n "$expect" ]]; then
    local got
    got="$(awk '/^=== STDERR ===/{f=1;next}/^\[EXIT/{f=0}f' "$out" | tr -d '\r' | sed '/^$/d')"
    [[ "$got" == "$expect" ]] || { echo "--- run output ---"; cat "$out"; fail "output mismatch (expected '$expect', got '$got')"; }
  fi
}

# ---------------------------------------------------------------------------
# 1. `x = 1` — GC-free; must link clean and run exit 0.
# ---------------------------------------------------------------------------
NEG_SRC="$TMP_DIR/neg.cr"
NEG_BIN="$TMP_DIR/neg.bin"
printf 'x = 1\n' >"$NEG_SRC"
set +e
"$COMPILER" "$NEG_SRC" -o "$NEG_BIN" >"$TMP_DIR/neg.link" 2>&1
neg_status=$?
set -e
[[ $neg_status -eq 0 && -x "$NEG_BIN" ]] || { echo "--- link ---"; cat "$TMP_DIR/neg.link"; fail "x=1 failed to build (status=$neg_status)"; }
grep -qE "Undefined symbols|_GC_base|_GC_realloc" "$TMP_DIR/neg.link" && { cat "$TMP_DIR/neg.link"; fail "x=1: undefined GC symbols leaked into link"; }
run_clean "$NEG_BIN"
echo "ok: x=1 builds, links clean, runs exit 0"

# ---------------------------------------------------------------------------
# 2. string-churn mix — the dynamic-String producer surface.
# ---------------------------------------------------------------------------
CHURN_SRC="$TMP_DIR/churn.cr"
CHURN_BIN="$TMP_DIR/churn.bin"
cat >"$CHURN_SRC" <<'CR'
table = {} of String => Array(String)
i = 0
while i < 40
  key = "k#{i % 5}"
  bucket = table[key]? || [] of String
  bucket << "v#{i}-#{i * 2}"
  table[key] = bucket
  i += 1
end

total = 0
sizes = String.build do |io|
  table.each do |k, vs|
    io << k
    io << ":"
    io << vs.size.to_s
    io << ";"
    total += vs.size
  end
end

joined = ("a" + "") + ("" + "b")
sl = "churn-src".to_slice
STDERR.puts "buckets=#{table.size} total=#{total} sizes=#{sizes} joined=#{joined} slb=#{sl.size}:#{sl[0]}"
STDERR.flush
CR
set +e
"$COMPILER" "$CHURN_SRC" -o "$CHURN_BIN" >"$TMP_DIR/churn.build" 2>&1
churn_status=$?
set -e
[[ $churn_status -eq 0 && -x "$CHURN_BIN" ]] || { echo "--- build ---"; cat "$TMP_DIR/churn.build"; fail "string-churn failed to build (status=$churn_status)"; }
# 40 inserts spread over 5 keys -> 5 buckets, 8 each, total 40.
# sizes string is order-dependent across Hash#each; assert the stable parts only.
run_clean "$CHURN_BIN"
churn_out="$(awk '/^=== STDERR ===/{f=1;next}/^\[EXIT/{f=0}f' "$TMP_DIR/churn.bin.run" | tr -d '\r' | sed '/^$/d')"
echo "string-churn stderr: $churn_out"
[[ "$churn_out" == *"buckets=5 total=40 "* ]] || fail "string-churn: bucket/total mismatch ($churn_out)"
[[ "$churn_out" == *"joined=ab "* ]] || fail "string-churn: concat-passthrough mismatch ($churn_out)"
[[ "$churn_out" == *"slb=9:99" ]] || fail "string-churn: slice alias mismatch ($churn_out)"  # 'c'=99
echo "ok: string-churn producer mix builds and runs clean"

# ---------------------------------------------------------------------------
# 3. OPT-IN: full s2b self-build of src/adamas.cr (heavy; ADAMAS_ER11_FULL=1).
# ---------------------------------------------------------------------------
if [[ "$ER11_FULL" == "1" ]]; then
  echo "ADAMAS_ER11_FULL=1: building s2b (src/adamas.cr) — this is heavy (minutes, multi-GB)"
  S2B="$TMP_DIR/s2b"
  set +e
  "$COMPILER" src/adamas.cr -o "$S2B" >"$TMP_DIR/s2b.build" 2>&1
  s2b_status=$?
  set -e
  [[ $s2b_status -eq 0 && -x "$S2B" ]] || { echo "--- s2b build (tail) ---"; tail -30 "$TMP_DIR/s2b.build"; fail "s2b build failed (status=$s2b_status)"; }
  # s2b must then build x=1 cleanly (the original startup-crash shape).
  S2B_OUT="$TMP_DIR/s2b_x1.bin"
  set +e
  "$S2B" "$NEG_SRC" -o "$S2B_OUT" >"$TMP_DIR/s2b_x1.link" 2>&1
  s2b_x1_status=$?
  set -e
  [[ $s2b_x1_status -eq 0 && -x "$S2B_OUT" ]] || { echo "--- s2b x=1 ---"; cat "$TMP_DIR/s2b_x1.link"; fail "s2b failed to build x=1 (the startup-crash shape; status=$s2b_x1_status)"; }
  run_clean "$S2B_OUT"
  echo "ok: s2b self-build + s2b(x=1) build/run clean"
else
  echo "SKIP: full s2b self-build (set ADAMAS_ER11_FULL=1 to enable — heavy, shared-machine guard)"
fi

echo "PASS: E-R11 s2b reproducer (bounded proxies$([[ "$ER11_FULL" == "1" ]] && echo " + full self-build"))"
exit 0
