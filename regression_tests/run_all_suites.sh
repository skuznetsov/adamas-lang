#!/bin/bash
# Run all regression test suites: original (68) + combined (20)
# Usage: ./regression_tests/run_all_suites.sh [path-to-compiler] [parallelism]

COMPILER="${1:-bin/crystal_v2}"
JOBS="${2:-4}"

echo "========================================"
echo " Crystal V2 Regression Test Suite"
echo "========================================"
echo ""

# Run original tests
echo "--- Original Tests (regression_tests/*.cr) ---"
regression_tests/run_all.sh "$COMPILER" "$JOBS"
orig_rc=$?
echo ""

# Run combined tests
echo "--- Combined Tests (regression_tests/combined/*.cr) ---"
regression_tests/run_combined.sh "$COMPILER" "$JOBS"
combined_rc=$?
echo ""

echo "========================================"
if [ $orig_rc -eq 0 ] && [ $combined_rc -eq 0 ]; then
  echo " ALL SUITES PASSED"
  exit 0
else
  echo " SOME TESTS FAILED"
  [ $orig_rc -ne 0 ] && echo "  - Original suite: FAILURES"
  [ $combined_rc -ne 0 ] && echo "  - Combined suite: FAILURES"
  exit 1
fi
