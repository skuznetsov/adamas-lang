#!/bin/bash
# Run all regression tests
# Usage: ./regression_tests/run_all.sh [path-to-compiler] [parallelism]
#
# Each .cr file can have "# EXPECT: <marker>" on any line.
# If present, the runner checks that marker appears in output.
# Otherwise, just checks for clean exit (code 0).

COMPILER="${1:-bin/adamas}"
JOBS="${2:-4}"
TIMEOUT=10
MAX_MEM=512
BIN_DIR="regression_tests/bin"

if [ ! -x "$COMPILER" ]; then
  echo "ERROR: Compiler not found at $COMPILER"
  echo "Build with: crystal build src/adamas.cr -o bin/adamas --error-trace"
  exit 1
fi

mkdir -p "$BIN_DIR"

# Single-test runner function — writes result to $BIN_DIR/$name.result
run_one_test() {
  local src="$1"
  local name=$(basename "$src" .cr)
  local bin_path="${BIN_DIR}/${name}"
  local result_path="${BIN_DIR}/${name}.result"

  # Compile
  compile_output=$("$COMPILER" "$src" 2>&1)
  if [ $? -ne 0 ]; then
    printf 'COMPILE_FAIL\n%s\n' "$(echo "$compile_output" | head -3)" > "$result_path"
    rm -f "regression_tests/${name}"
    return
  fi

  # Move binary if compiler placed it next to source
  if [ -f "regression_tests/${name}" ]; then
    mv "regression_tests/${name}" "$bin_path"
  fi

  if [ ! -f "$bin_path" ]; then
    echo "NO_BINARY" > "$result_path"
    return
  fi

  # Extract expected marker
  local expect=$(grep -m1 '^# EXPECT:' "$src" | sed 's/^# EXPECT: *//')

  # Run with timeout
  local output=$(scripts/run_safe.sh "$bin_path" $TIMEOUT $MAX_MEM 2>/dev/null)
  local exit_code=$?
  rm -f "$bin_path"

  if [ -n "$expect" ]; then
    if echo "$output" | grep -qF "$expect"; then
      echo "PASS" > "$result_path"
    elif [ $exit_code -ne 0 ]; then
      printf 'CRASH\n%s\n' "$(echo "$output" | tail -3)" > "$result_path"
    else
      printf 'OUTPUT_MISMATCH\n%s\n%s\n' "$expect" "$(echo "$output" | tail -5)" > "$result_path"
    fi
  else
    if [ $exit_code -eq 0 ]; then
      echo "PASS" > "$result_path"
    else
      printf 'CRASH\n%s\n' "$(echo "$output" | tail -3)" > "$result_path"
    fi
  fi
}

export -f run_one_test
export COMPILER TIMEOUT MAX_MEM BIN_DIR

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
  rm -f "$result_path"
done

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ $FAIL -eq 0 ] && exit 0 || exit 1
