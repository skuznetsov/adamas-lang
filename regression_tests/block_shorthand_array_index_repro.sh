#!/usr/bin/env bash
# Regression: block shorthand `&.[idx]` must lower Array element access as the
# Int32 overload, not as Array#[](Range). Pre-fix, `parsed.map(&.[0])` selected
# Array(String)#[](Range) and passed the Int32 index as a Range pointer, crashing
# in Range#begin.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block-shorthand-array-index.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

compile_and_expect() {
  local name="$1"
  local expected="$2"
  local src="$TMP_DIR/$name.cr"
  local bin="$TMP_DIR/$name.bin"
  local compile_log="$TMP_DIR/$name.compile.log"
  local run_log="$TMP_DIR/$name.run.log"

  cat >"$src"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 4096 "$src" -o "$bin" >"$compile_log" 2>&1
  local compile_status=$?
  set -e

  if [[ $compile_status -ne 0 ]]; then
    echo "FAIL: $name did not compile (status $compile_status)" >&2
    tail -100 "$compile_log" >&2
    exit 1
  fi

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$bin" 10 512 >"$run_log" 2>&1
  local run_status=$?
  set -e

  local stdout
  stdout="$(awk '/^=== STDOUT ===/{flag=1;next}/^=== STDERR ===/{flag=0}flag' "$run_log" | tr -d '\r')"

  if [[ $run_status -eq 0 && "$stdout" == "$expected" ]]; then
    echo "PASS: $name"
    return
  fi

  echo "FAIL: $name" >&2
  echo "run_status: $run_status" >&2
  echo "expected stdout:" >&2
  printf '%s\n' "$expected" >&2
  echo "actual stdout:" >&2
  printf '%s\n' "$stdout" >&2
  echo "--- run log tail ---" >&2
  tail -100 "$run_log" >&2
  exit 1
}

compile_and_expect "shorthand_literal" "a" <<'CR'
parsed = [["a", "b"], ["a", "c"]]
column = parsed.map(&.[0]).uniq
puts column.join(",")
CR

compile_and_expect "shorthand_local" "a" <<'CR'
parsed = [["a", "b"], ["a", "c"]]
i = 0
column = parsed.map(&.[i]).uniq
puts column.join(",")
CR

compile_and_expect "explicit_block" "a" <<'CR'
parsed = [["a", "b"], ["a", "c"]]
i = 0
column = parsed.map { |row| row[i] }.uniq
puts column.join(",")
CR

compile_and_expect "direct_range_slice" "a" <<'CR'
row = ["a", "b"]
slice = row[0...1]
puts slice.join(",")
CR

echo "block_shorthand_array_index_ok"
