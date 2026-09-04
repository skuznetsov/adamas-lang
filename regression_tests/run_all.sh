#!/bin/bash
# Run all regression tests
# Usage: ./regression_tests/run_all.sh [path-to-compiler] [parallelism]
# REGRESSION_COMPILE_TIMEOUT=120 and REGRESSION_COMPILE_MAX_MEM=4096 bound each compile.
# REGRESSION_KEEP_LOGS=1 retains per-test exit codes and full supervisor output.
#
# Each .cr file can have "# EXPECT: <marker>" on any line.
# If present, the runner checks that marker appears in output.
# Otherwise, just checks for clean exit (code 0).

COMPILER="${1:-bin/adamas}"
JOBS="${2:-8}"   # default = performance-core count; memory per compile ~0.4GB so RAM is not the limit
TIMEOUT=10
MAX_MEM=512
COMPILE_TIMEOUT="${REGRESSION_COMPILE_TIMEOUT:-120}"
COMPILE_MAX_MEM="${REGRESSION_COMPILE_MAX_MEM:-4096}"
KEEP_LOGS="${REGRESSION_KEEP_LOGS:-0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"

for budget in "$JOBS" "$COMPILE_TIMEOUT" "$COMPILE_MAX_MEM"; do
  if ! [[ "$budget" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: parallelism and compile budgets must be positive integers" >&2
    exit 2
  fi
done
case "$KEEP_LOGS" in
  0|1) ;;
  *) echo "ERROR: REGRESSION_KEEP_LOGS must be 0 or 1" >&2; exit 2 ;;
esac
# The golden reader requires the supervisor's captured-output framing.
unset RUN_SAFE_PASSTHROUGH_STDIO RUN_SAFE_RESOURCE_FILE

if [ ! -x "$COMPILER" ]; then
  echo "ERROR: Compiler not found at $COMPILER"
  echo "Build with: crystal build src/adamas.cr -o bin/adamas --error-trace"
  exit 1
fi

# Only this invocation can produce a candidate executable in this directory.
BIN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/adamas_regression_all.XXXXXX") || exit 2

# Single-test runner function — writes result to $BIN_DIR/$name.result
run_one_test() {
  local src="$1"
  local name=$(basename "$src" .cr)
  local artifact_dir="${BIN_DIR}/${name}.artifacts"
  local bin_path="${artifact_dir}/${name}"
  local result_path="${BIN_DIR}/${name}.result"

  # Keep compiler-owned output and every unknown sibling artifact in a
  # per-test directory. Logs and verdict files intentionally stay outside so
  # REGRESSION_KEEP_LOGS can retain raw evidence without retaining binaries or
  # generated IR.
  if ! mkdir -p "$artifact_dir"; then
    printf 'COMPILE_FAIL\nfailed to create artifact directory: %s\n' "$artifact_dir" > "$result_path"
    return
  fi

  # Bound compilation separately from execution and preserve its own status.
  local compile_log="${BIN_DIR}/${name}.compile.log"
  local compile_rc
  local compile_args=("$src" -o "$bin_path")
  "$SAFE_RUN" "$COMPILER" "$COMPILE_TIMEOUT" "$COMPILE_MAX_MEM" "${compile_args[@]}" > "$compile_log" 2>&1
  compile_rc=$?
  printf '%s\n' "$compile_rc" > "${BIN_DIR}/${name}.compile.exit"
  if [ "$compile_rc" -ne 0 ]; then
    printf 'COMPILE_FAIL\n%s\n' "$(tail -10 "$compile_log")" > "$result_path"
    rm -rf "$artifact_dir"
    return
  fi

  if [ ! -f "$bin_path" ] || [ ! -x "$bin_path" ]; then
    echo "NO_BINARY" > "$result_path"
    rm -rf "$artifact_dir"
    return
  fi

  # Extract expected marker
  local expect=$(grep -m1 '^# EXPECT:' "$src" | sed 's/^# EXPECT: *//')

  # Run with timeout
  local runtime_log="${BIN_DIR}/${name}.runtime.log"
  local exit_code
  "$SAFE_RUN" "$bin_path" "$TIMEOUT" "$MAX_MEM" > "$runtime_log" 2>&1
  exit_code=$?
  printf '%s\n' "$exit_code" > "${BIN_DIR}/${name}.runtime.exit"
  rm -rf "$artifact_dir"

  # A matching marker cannot turn a failed process into a passing test.
  if [ "$exit_code" -ne 0 ]; then
    printf 'CRASH\n%s\n' "$(tail -3 "$runtime_log")" > "$result_path"
    return
  fi

  if [ -n "$expect" ]; then
    if grep -qF "$expect" "$runtime_log"; then
      echo "PASS" > "$result_path"
    else
      printf 'OUTPUT_MISMATCH\n%s\n%s\n' "$expect" "$(tail -5 "$runtime_log")" > "$result_path"
    fi
  else
    echo "PASS" > "$result_path"
  fi
}

export -f run_one_test
export COMPILER TIMEOUT MAX_MEM BIN_DIR SAFE_RUN COMPILE_TIMEOUT COMPILE_MAX_MEM

# Run tests in parallel using xargs
SOURCES=(regression_tests/*.cr)
printf '%s\n' "${SOURCES[@]}" | xargs -P "$JOBS" -I {} bash -c 'run_one_test "$@"' _ {}

# Collect results (sorted order)
PASS=0
FAIL=0
for src in "${SOURCES[@]}"; do
  name=$(basename "$src" .cr)
  result_path="${BIN_DIR}/${name}.result"

  if [ ! -f "$result_path" ]; then
    echo "FAIL (unknown): $name"
    FAIL=$((FAIL + 1))
    continue
  fi

  status=$(head -1 "$result_path")
  case "$status" in
    PASS)
      echo "PASS: $name"
      PASS=$((PASS + 1))
      ;;
    COMPILE_FAIL)
      echo "FAIL (compile): $name"
      tail -n +2 "$result_path" | sed 's/^/  /'
      FAIL=$((FAIL + 1))
      ;;
    NO_BINARY)
      echo "FAIL (no binary): $name"
      FAIL=$((FAIL + 1))
      ;;
    CRASH)
      echo "FAIL (crash/timeout): $name"
      tail -n +2 "$result_path" | sed 's/^/  Output: /'
      FAIL=$((FAIL + 1))
      ;;
    OUTPUT_MISMATCH)
      expect_line=$(sed -n '2p' "$result_path")
      echo "FAIL (output): $name — expected '$expect_line'"
      tail -n +3 "$result_path" | sed 's/^/  Output: /'
      FAIL=$((FAIL + 1))
      ;;
    *)
      echo "FAIL (unknown status): $name"
      FAIL=$((FAIL + 1))
      ;;
  esac
done

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
# xargs has joined all workers; cleanup cannot race an active compiler.
if [ "$KEEP_LOGS" = 1 ]; then
  echo "Logs: $BIN_DIR"
else
  rm -rf "$BIN_DIR"
fi
[ $FAIL -eq 0 ] && exit 0 || exit 1
