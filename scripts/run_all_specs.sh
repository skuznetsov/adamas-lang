#!/bin/bash
# Run the full compiler spec suite file-by-file.
# The specs cannot be compiled into a single binary (duplicate top-level
# `alias Frontend`/`alias Semantic` across ~45 files), so each *_spec.cr is
# compiled+run independently. Results are tallied into a summary.
#
# Usage: scripts/run_all_specs.sh [parallelism] [per-file-timeout-sec]
# NOTE: avoids bash-4 builtins (mapfile) so it works with macOS /bin/bash 3.2.

JOBS="${1:-4}"
TIMEOUT="${2:-300}"
OUTDIR="$(mktemp -d /tmp/adamas_spec_run.XXXXXX)"
echo "Spec output dir: $OUTDIR  (jobs=$JOBS timeout=${TIMEOUT}s)"

TOTAL=$(find spec -name '*_spec.cr' | wc -l | tr -d ' ')
echo "Total spec files: $TOTAL"

run_one() {
  local f="$1"
  local safe="${f//\//_}"
  local log="$OUTDIR/$safe.log"
  local rc
  if timeout "$TIMEOUT" crystal spec "$f" --no-color >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  local summary
  summary=$(grep -E "examples?,.*failures?" "$log" | tail -1)
  if [ -z "$summary" ]; then
    if [ "$rc" -eq 124 ]; then
      echo "TIMEOUT|$f|"
    else
      echo "COMPILE_FAIL|$f|rc=$rc $(grep -m1 -E 'Error:' "$log")"
    fi
  else
    local fails
    fails=$(echo "$summary" | grep -oE "[0-9]+ failures?" | grep -oE "[0-9]+")
    if [ "${fails:-0}" -eq 0 ] && [ "$rc" -eq 0 ]; then
      echo "PASS|$f|$summary"
    else
      echo "FAIL|$f|$summary"
    fi
  fi
}
export -f run_one
export OUTDIR TIMEOUT

find spec -name '*_spec.cr' | sort | \
  xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {} > "$OUTDIR/results.txt"

echo ""
echo "======================================== SPEC SUMMARY ========================================"
sort "$OUTDIR/results.txt" > "$OUTDIR/results_sorted.txt"
pass=$(grep -c '^PASS|' "$OUTDIR/results.txt")
fail=$(grep -c '^FAIL|' "$OUTDIR/results.txt")
cfail=$(grep -c '^COMPILE_FAIL|' "$OUTDIR/results.txt")
tout=$(grep -c '^TIMEOUT|' "$OUTDIR/results.txt")
echo "Files: $TOTAL  |  PASS=$pass  FAIL=$fail  COMPILE_FAIL=$cfail  TIMEOUT=$tout"
echo ""
echo "--- Non-passing files ---"
grep -vE '^PASS\|' "$OUTDIR/results_sorted.txt" || echo "(none)"
echo ""
echo "--- Aggregate examples/failures ---"
awk -F'|' '{print $3}' "$OUTDIR/results.txt" | grep -oE "[0-9]+ examples?" | grep -oE "[0-9]+" | awk '{s+=$1} END{print "total examples: " s}'
awk -F'|' '{print $3}' "$OUTDIR/results.txt" | grep -oE "[0-9]+ failures?" | grep -oE "[0-9]+" | awk '{s+=$1} END{print "total failures: " s}'
echo "Logs: $OUTDIR"
