#!/usr/bin/env bash
# Regression: Hash default providers must store a valid Proc-backed default
# provider. `Hash.new(default_value)` forwards through a default block, and
# `Hash.new { ... }` passes an explicit block; both must work on missing-key
# lookup. The initial_capacity-only constructor is a negative control because it
# does not install a default provider.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_default_provider_proc.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

write_case() {
  local name="$1"
  local body="$2"
  printf '%s\nSTDOUT.flush\n' "$body" >"$TMP_DIR/$name.cr"
}

write_case int_default 'h = Hash(String, Int32).new(0); puts "RESULT=#{h["missing"]}"'
write_case int_block 'h = Hash(String, Int32).new { 7 }; puts "RESULT=#{h["missing"]}"'
write_case int_capacity 'h = Hash(String, Int32).new(initial_capacity: 0); puts "RESULT=#{h.size}"'
write_case str_default 'h = Hash(String, String).new("x"); puts "RESULT=#{h["missing"]}"'

run_case() {
  local name="$1"
  local expected="$2"
  local src="$TMP_DIR/$name.cr"
  local bin="$TMP_DIR/$name.bin"
  local compile_log="$TMP_DIR/$name.compile.log"
  local run_log="$TMP_DIR/$name.run.log"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 "$src" -o "$bin" >"$compile_log" 2>&1
  local compile_status=$?
  set -e
  if [[ $compile_status -ne 0 ]]; then
    echo "FAIL: $name compile failed (status $compile_status)"
    cat "$compile_log"
    return 1
  fi

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$bin" 5 512 >"$run_log" 2>&1
  local run_status=$?
  set -e

  local result_line
  result_line="$(grep -E '^RESULT=' "$run_log" | head -1 || true)"
  if [[ $run_status -eq 0 && "$result_line" == "$expected" ]]; then
    echo "PASS: $name"
    return 0
  fi

  echo "FAIL: $name"
  echo "expected: $expected"
  echo "actual:   ${result_line:-<no RESULT line>} (status $run_status)"
  cat "$run_log"
  return 1
}

fail=0
run_case int_default "RESULT=0" || fail=1
run_case int_block "RESULT=7" || fail=1
run_case int_capacity "RESULT=0" || fail=1
run_case str_default "RESULT=x" || fail=1

if [[ $fail -eq 0 ]]; then
  echo "PASS: Hash default providers preserve Proc/default semantics"
  exit 0
fi

echo "FAIL: Hash default provider regression reproduced"
exit 1
