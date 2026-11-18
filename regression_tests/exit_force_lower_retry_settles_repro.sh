#!/usr/bin/env bash
# Regression: a program that calls `exit` compiles and keeps its status.
#
# `exit` lowers Crystal::AtExitHandlers.run, which reaches
# Crystal::System.print_error and its integer formatting helpers through
# nested forced return-type lowering. Three continuations of the force-lower
# retry driver were lost, and the suspended exact result escaped as
# "pending source result ...":
#   - an ordinary caller re-recorded the replayed call with the same ABI
#     shell but without source facts, and the replay guard treated that
#     weaker record as a competing demand (Int32#tdiv in to_int_slice_impl);
#   - a provisional body that recursed into itself waited on its own result;
#   - a retry without an exact recipe was treated as stale, ran before its
#     queued producers settled, and was dropped (print_error).
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/exit-force-lower-retry.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
STDERR.puts "before"
exit 3
CR

expected='before'
expected_status=3

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH' || true; }

run_program() {
  local bin="$1"
  set +e
  out="$("$SAFE_RUNNER" "$bin" 5 256 2>&1)"
  status=$?
  set -e
  printed="$(printf '%s\n' "$out" | strip)"
}

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  run_program "$WORK_DIR/m_oracle"
  if [[ $status -ne $expected_status || "$printed" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: exit=$status out=$printed" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

run_program "$WORK_DIR/m"
if [[ $status -ne $expected_status || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status (expected $expected_status)" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: exit program compiles and returns its status"
