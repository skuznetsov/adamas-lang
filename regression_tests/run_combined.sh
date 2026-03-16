#!/bin/bash
# Run combined regression tests (fewer compilations, more coverage per file)
# Usage: ./regression_tests/run_combined.sh [path-to-compiler] [parallelism]
#
# Each .cr file must have "# EXPECT: <marker>" on any line.
# The runner checks that marker appears in output.

COMPILER="${1:-bin/crystal_v2}"
JOBS="${2:-4}"
TIMEOUT=15
MAX_MEM=512
BIN_DIR="regression_tests/combined/bin"

if [ ! -x "$COMPILER" ]; then
  echo "ERROR: Compiler not found at $COMPILER"
  echo "Build with: crystal build src/crystal_v2.cr -o bin/crystal_v2 --error-trace"
  exit 1
fi

mkdir -p "$BIN_DIR"

run_one_test() {
  local src="$1"
  local name=$(basename "$src" .cr)
  local bin_path="${BIN_DIR}/${name}"
  local result_path="${BIN_DIR}/${name}.result"

  # Compile
  compile_output=$("$COMPILER" "$src" 2>&1)
  local compile_rc=$?

  if [ $compile_rc -ne 0 ]; then
    printf 'COMPILE_FAIL\n%s\n' "$(echo "$compile_output" | tail -10)" > "$result_path"
    rm -f "regression_tests/combined/${name}"
    return
  fi

  # Move binary if compiler placed it next to source
  if [ -f "regression_tests/combined/${name}" ]; then
    mv "regression_tests/combined/${name}" "$bin_path"
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
      printf 'CRASH\n%s\n' "$(echo "$output" | tail -5)" > "$result_path"
    else
      printf 'OUTPUT_MISMATCH\nexpected: %s\ngot:\n%s\n' "$expect" "$(echo "$output" | tail -10)" > "$result_path"
    fi
  else
    if [ $exit_code -eq 0 ]; then
      echo "PASS" > "$result_path"
    else
      printf 'CRASH\n%s\n' "$(echo "$output" | tail -5)" > "$result_path"
    fi
  fi
}

export -f run_one_test
export COMPILER TIMEOUT MAX_MEM BIN_DIR

echo "=== Combined Regression Tests ==="
echo "Compiler: $COMPILER"
echo "Parallelism: $JOBS"
echo ""

# Run tests in parallel
SOURCES=(regression_tests/combined/*.cr)
printf '%s\n' "${SOURCES[@]}" | xargs -P "$JOBS" -I {} bash -c 'run_one_test "$@"' _ {}

# Collect results
PASS=0
FAIL=0

for src in "${SOURCES[@]}"; do
  name=$(basename "$src" .cr)
  result_path="${BIN_DIR}/${name}.result"

  if [ ! -f "$result_path" ]; then
    printf "  FAIL (unknown): %s\n" "$name"
    FAIL=$((FAIL + 1))
    continue
  fi

  status=$(head -1 "$result_path")

  case "$status" in
    PASS)
      printf "  PASS: %s\n" "$name"
      PASS=$((PASS + 1))
      ;;
    COMPILE_FAIL)
      printf "  FAIL (compile): %s\n" "$name"
      tail -n +2 "$result_path" | sed 's/^/    /'
      FAIL=$((FAIL + 1))
      ;;
    NO_BINARY)
      printf "  FAIL (no binary): %s\n" "$name"
      FAIL=$((FAIL + 1))
      ;;
    CRASH)
      printf "  FAIL (crash): %s\n" "$name"
      tail -n +2 "$result_path" | sed 's/^/    /'
      FAIL=$((FAIL + 1))
      ;;
    OUTPUT_MISMATCH)
      printf "  FAIL (output): %s\n" "$name"
      tail -n +2 "$result_path" | sed 's/^/    /'
      FAIL=$((FAIL + 1))
      ;;
    *)
      printf "  FAIL (unknown status): %s\n" "$name"
      FAIL=$((FAIL + 1))
      ;;
  esac
  rm -f "$result_path"
done

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) combined tests"
[ $FAIL -eq 0 ] && exit 0 || exit 1
