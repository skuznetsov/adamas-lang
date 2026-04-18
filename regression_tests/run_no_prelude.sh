#!/bin/bash
# Fast compiler-reducer tier — all sources compiled with --no-prelude.
# Usage: ./regression_tests/run_no_prelude.sh [path-to-compiler] [parallelism]
#
# Each .cr file may declare a `# EXPECT: <substring>` line (first match wins).
# If a sibling `<name>.out` exists, program stdout must match it byte-for-byte
# (strict mode), overriding the substring check. Generate goldens with reference
# Crystal or the current compiler when establishing a new test.
#
# This tier exists because full-prelude compiles pay ~16s per source. Reducers
# that probe compiler-only behavior (HIR/MIR/LLVM lowering) belong here, not in
# run_all.sh. Tests that require stdlib semantics (Hash layout, String::Builder
# @bytesize, Fiber, Channel, etc.) belong in regression_tests/combined/.

COMPILER="${1:-bin/crystal_v2}"
JOBS="${2:-4}"
TIMEOUT=10
MAX_MEM=256
BIN_DIR="regression_tests/no_prelude/bin"

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

  local compile_output
  compile_output=$("$COMPILER" --no-prelude "$src" -o "$bin_path" 2>&1)
  local compile_rc=$?

  if [ $compile_rc -ne 0 ]; then
    printf 'COMPILE_FAIL\n%s\n' "$(echo "$compile_output" | tail -5)" > "$result_path"
    return
  fi

  if [ ! -f "$bin_path" ]; then
    # Compiler placed binary next to source; move it.
    local stray="$(dirname "$src")/${name}"
    if [ -f "$stray" ]; then
      mv "$stray" "$bin_path"
    else
      echo "NO_BINARY" > "$result_path"
      return
    fi
  fi

  local output
  output=$(scripts/run_safe.sh "$bin_path" $TIMEOUT $MAX_MEM 2>/dev/null)
  local exit_code=$?
  rm -f "$bin_path" "${bin_path}.ll"

  local golden_path="${src%.cr}.out"
  local actual_tmp
  actual_tmp=$(mktemp "${TMPDIR:-/tmp}/run_no_prelude_stdout.XXXXXX")
  echo "$output" | awk '/^=== STDOUT ===$/{p=1;next}/^=== STDERR ===$/{p=0}p' > "$actual_tmp"

  if [ -f "$golden_path" ]; then
    if [ $exit_code -ne 0 ]; then
      printf 'CRASH\n%s\n' "$(echo "$output" | tail -5)" > "$result_path"
    elif cmp -s "$actual_tmp" "$golden_path"; then
      echo "PASS" > "$result_path"
    else
      {
        printf 'GOLDEN_MISMATCH\ngolden: %s\n' "$golden_path"
        diff -u "$golden_path" "$actual_tmp" || true
      } > "$result_path"
    fi
    rm -f "$actual_tmp"
    return
  fi
  rm -f "$actual_tmp"

  local expect
  expect=$(grep -m1 '^# EXPECT:' "$src" | sed 's/^# EXPECT: *//' || true)

  if [ -n "$expect" ]; then
    if echo "$output" | grep -qF "$expect"; then
      echo "PASS" > "$result_path"
    elif [ $exit_code -ne 0 ]; then
      printf 'CRASH\n%s\n' "$(echo "$output" | tail -5)" > "$result_path"
    else
      printf 'OUTPUT_MISMATCH\nexpected: %s\ngot:\n%s\n' "$expect" "$(echo "$output" | tail -5)" > "$result_path"
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

SOURCES=(regression_tests/no_prelude/*.cr)
if [ "${SOURCES[0]}" = "regression_tests/no_prelude/*.cr" ]; then
  echo "=== No-Prelude Reducer Tier ==="
  echo "No tests found in regression_tests/no_prelude/"
  exit 0
fi

echo "=== No-Prelude Reducer Tier ==="
echo "Compiler: $COMPILER"
echo "Parallelism: $JOBS"
echo "Tests: ${#SOURCES[@]}"
echo ""

SECONDS=0
printf '%s\n' "${SOURCES[@]}" | xargs -P "$JOBS" -I {} bash -c 'run_one_test "$@"' _ {}
ELAPSED=$SECONDS

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
    GOLDEN_MISMATCH)
      printf "  FAIL (golden): %s\n" "$name"
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
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) no-prelude tests (${ELAPSED}s wall)"
[ $FAIL -eq 0 ] && exit 0 || exit 1
