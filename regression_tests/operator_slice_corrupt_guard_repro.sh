#!/usr/bin/env bash
# Regression guard for: fix(hir) 3230c001 — length-guard operator slice before
# String.new in unary lowering.
#
# Background: 9f5e4acc made unary_operator_text / safe_unary_operator_string
# prefer safe_slice_to_string(node.operator). When the #4 String<->Slice
# repr-flip corrupts the operator slice slot (observed {ptr=0x100000000,
# size=311}), String.new(slice) memmoves past mapped memory and SIGSEGVs while
# force_lowering the Dir.glob path. The fix length-guards the slice (1-4 bytes)
# so a corrupt huge-size slice falls through to the bounded source-span path.
#
# The crash is NON-DETERMINISTIC (ASLR decides mapped vs unmapped overshoot),
# ~7.5% pre-fix on this 3-line probe. A single run proves nothing — so this
# script runs N iterations and FAILS only on a SIGSEGV (the memmove crash the
# fix targets). rc=1 (a rarer, separate #4 manifestation) is tolerated.
#
# This is a MANUAL repro (run_all.sh globs *.cr, not *.sh). Run after touching
# unary operator lowering or the #4 repr-flip surface.
#
# Pre-fix A/B (N=40 standalone, ASLR on): SIGSEGV 3/40.
# Post-fix: SIGSEGV 0/40 (+0 in 30 lldb tries, +0 in a 60-iter hunt).
set -u
cd "$(dirname "$0")/.." || exit 2

COMPILER="${1:-bin/adamas}"
N="${2:-40}"
PROBE=regression_tests/stage2_dir_glob_dir_probe.cr
OUT=/tmp/operator_slice_guard_probe.bin
TO=/usr/local/bin/timeout
[ -x "$TO" ] || TO=timeout

if [ ! -x "$COMPILER" ]; then
  echo "ERROR: compiler not found at $COMPILER" >&2
  exit 2
fi

segv=0 other=0 ok=0
for ((i = 1; i <= N; i++)); do
  "$TO" 25 "$COMPILER" "$PROBE" -o "$OUT" >/dev/null 2>&1
  rc=$?
  # bash reports a signal-killed child as 128+signum; SIGSEGV=11 -> 139.
  # Some builds catch the fault and exit 11 directly. Treat both as SIGSEGV.
  if [ "$rc" -eq 0 ]; then
    ok=$((ok + 1))
  elif [ "$rc" -eq 139 ] || [ "$rc" -eq 11 ]; then
    segv=$((segv + 1))
  else
    other=$((other + 1)) # rc=124 hang or rc=1 separate #4 path — tolerated
  fi
done
rm -f "$OUT"

echo "operator-slice corrupt-guard: $segv SIGSEGV / $other other / $ok ok  (N=$N)"
if [ "$segv" -ne 0 ]; then
  echo "FAIL: operator-slice memmove SIGSEGV reproduced — guard regressed" >&2
  exit 1
fi
echo "PASS: no operator-slice SIGSEGV in $N runs"
exit 0
