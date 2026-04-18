#!/usr/bin/env bash
# Known-red reducer for: spawn { ... } captures block param / helper method arg
# via a GLOBAL class var (@__closure__classvar____closure_cell_N) instead of a
# per-instance heap env. Loop-spawned fibers therefore clobber each other and
# all read the last-written capture.
#
# Documented in memory/closure_capture_via_global_cells_bug.md. Behind Part 6
# of examples/bench_comprehensive.cr (Fibers total=799980000 expected).
#
# Exit contract:
#   0 — reproduced: BOTH expected FAIL strings observed with exact sums.
#   1 — not reproduced: both probes printed the _ok markers (bug fixed).
#   2 — invalid invocation (missing compiler arg).
#   >2 — unexpected failure (compile error, partial reproduction with different
#        sums, segfault, timeout, etc.). These flag a distinct bug that
#        shouldn't be masked by this known-red guard.
set -euo pipefail

EXPECTED_A='probe_block_param_FAIL sum=16'
EXPECTED_B='probe_helper_arg_FAIL sum=12'

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spawn_capture.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
# Probe A: `.times do |i| spawn { send(i) }` — block param capture.
ch_a = Channel(Int64).new
4.times do |i|
  spawn { ch_a.send(i.to_i64) }
end
sum_a = 0_i64
pk = 0
while pk < 4
  sum_a += ch_a.receive
  pk += 1
end
if sum_a == 6_i64
  puts "probe_block_param_ok"
else
  puts "probe_block_param_FAIL sum=#{sum_a}"
end

# Probe B: helper method arg capture.
def send_id(ch : Channel(Int64), v : Int32)
  spawn { ch.send(v.to_i64) }
end

ch_b = Channel(Int64).new
4.times do |i|
  send_id(ch_b, i)
end
sum_b = 0_i64
pk2 = 0
while pk2 < 4
  sum_b += ch_b.receive
  pk2 += 1
end
if sum_b == 6_i64
  puts "probe_helper_arg_ok"
else
  puts "probe_helper_arg_FAIL sum=#{sum_b}"
end
CR

compile_cmd=()
if [[ "$(basename "$COMPILER")" == "crystal" ]]; then
  compile_cmd=("$COMPILER" build "$SRC" -o "$BIN")
else
  compile_cmd=("$COMPILER" "$SRC" -o "$BIN")
fi

set +e
"${compile_cmd[@]}" >"$TMP_DIR/compile.out" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "unexpected: compile failed with status=$compile_status" >&2
  tail -20 "$TMP_DIR/compile.out" >&2
  exit 3
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 10 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

have_a_fail=0
have_b_fail=0
have_a_ok=0
have_b_ok=0
grep -qF "$EXPECTED_A"            "$RUN_LOG" && have_a_fail=1 || true
grep -qF "$EXPECTED_B"            "$RUN_LOG" && have_b_fail=1 || true
grep -qF "probe_block_param_ok"   "$RUN_LOG" && have_a_ok=1   || true
grep -qF "probe_helper_arg_ok"    "$RUN_LOG" && have_b_ok=1   || true

if [[ $have_a_fail -eq 1 && $have_b_fail -eq 1 ]]; then
  echo "reproduced: both probes failed with expected sums (16, 12)"
  exit 0
fi

if [[ $have_a_ok -eq 1 && $have_b_ok -eq 1 ]]; then
  echo "not reproduced: both probes printed _ok markers (bug likely fixed)"
  cat "$RUN_LOG"
  exit 1
fi

echo "unexpected: partial/unknown reproduction (status=$run_status)" >&2
echo "  expected FAIL A: $EXPECTED_A (seen=$have_a_fail)" >&2
echo "  expected FAIL B: $EXPECTED_B (seen=$have_b_fail)" >&2
echo "  probe A _ok marker seen=$have_a_ok" >&2
echo "  probe B _ok marker seen=$have_b_ok" >&2
echo "--- run log tail ---" >&2
tail -20 "$RUN_LOG" >&2
exit 4
