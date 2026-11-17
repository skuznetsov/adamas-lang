#!/usr/bin/env bash
# Regression: an exception raised through the stdlib must reach the rescue
# frames the compiler emits.
#
# `raise` is an ordinary overloadable call, so every raise runs the stdlib
# chain raise -> raise_without_backtrace -> fun __crystal_raise, whose source
# body calls _Unwind_RaiseException. Rescue frames here are setjmp/longjmp
# records, not unwind tables, so that unwinder returned END_OF_STACK: no
# rescue ever ran, and the process printed "Failed to raise an exception" and
# hung in print_backtrace. The platform primitive now hands the exception
# object to the compiler's raise runtime.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stdlib-raise-rescue.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class MyErr < Exception
end

def boom
  raise "boom"
end

def assert_present(x : Int32?)
  x.not_nil!
end

def rethrow
  boom
rescue e
  raise MyErr.new("wrapped #{e.message}")
end

begin
  boom
rescue ex
  STDERR.puts "a #{ex.message} #{ex.class}"
end

begin
  nil.not_nil!
rescue
  STDERR.puts "b"
end

begin
  assert_present(nil)
rescue e : NilAssertionError
  STDERR.puts "c #{e.class}"
end

begin
  raise MyErr.new("mine")
rescue e : ArgumentError
  STDERR.puts "wrong"
rescue e : MyErr
  STDERR.puts "d #{e.message}"
end

begin
  rethrow
rescue e : MyErr
  STDERR.puts "e #{e.message}"
end

value = begin
  assert_present(nil) + 1
rescue NilAssertionError
  -1
end
STDERR.puts value
STDERR.puts "done"
CR

cat > "$WORK_DIR/u.cr" <<'CR'
STDERR.puts "start"
raise ArgumentError.new("top")
CR

expected='a boom Exception
b
c NilAssertionError
d mine
e wrapped boom
-1
done'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

for program in m u; do
  if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/$program.cr" -o "$WORK_DIR/$program" > "$WORK_DIR/$program.build.log" 2>&1 || [[ ! -x "$WORK_DIR/$program" ]]; then
    echo "FAIL: $program.cr did not compile" >&2
    strip < "$WORK_DIR/$program.build.log" | tail -5 >&2
    exit 1
  fi
done

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: rescue program exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

# An unhandled exception must reach Crystal.main's rescue: report and exit 1.
set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/u" 5 256 2>&1)"
set -e
first="$(printf '%s\n' "$out" | strip | sed -n 1,2p)"
if ! printf '%s\n' "$out" | grep -q '^\[EXIT: 1\]' ||
   [[ "$first" != $'start\nUnhandled exception: top (ArgumentError)' ]]; then
  echo "FAIL: unhandled exception was not reported with exit 1" >&2
  printf '%s\n' "$out" | head -5 >&2
  exit 1
fi

echo "PASS: stdlib raise reaches setjmp rescue frames"
