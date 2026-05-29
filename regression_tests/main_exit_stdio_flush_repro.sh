#!/usr/bin/env bash
# Regression test: the final stdio write before normal program termination
# must not lose its tail.
#
# Bug: the backend synthesizes the C `@main` (emit_entrypoint_if_needed) which
# calls `__adamas_main` and returns straight into the C runtime, bypassing the
# stdlib `Crystal.main`/`Crystal.exit` teardown that flushes STDOUT/STDERR. The
# last buffered write before a normal (fall-through) exit was therefore lost:
# `puts("text")` printed only "te", `STDERR.puts("err-text")` only "err-te",
# etc. Adding a trailing `exit(0)` / `STDOUT.flush` masked it. Programs that
# call `exit(...)` were unaffected because `Crystal.exit` already flushes.
#
# Fix: lower_main emits `STDOUT.flush; STDERR.flush` (via IO::FileDescriptor#flush)
# as the last acts of __adamas_main on the live fall-through path.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/main_exit_flush.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail=0

run_case() {
  local name="$1" src="$2" expect="$3"
  local cr="$TMP_DIR/$name.cr" bin="$TMP_DIR/$name.bin" out="$TMP_DIR/$name.out"
  printf '%s' "$src" >"$cr"
  if ! "$COMPILER" "$cr" -o "$bin" >"$TMP_DIR/$name.compile" 2>&1; then
    echo "FAIL[$name]: compile error"; cat "$TMP_DIR/$name.compile"; fail=1; return
  fi
  "$bin" >"$out" 2>"$TMP_DIR/$name.err" || true
  local got
  got="$(cat "$out")"
  if [[ "$got" == "$expect" ]]; then
    echo "PASS[$name]: [$got]"
  else
    echo "FAIL[$name]: expected [$expect] got [$got]"; fail=1
  fi
}

# Bare last-statement puts must print the full string (was truncated to "te").
run_case puts_text 'puts("text")' "text"

# Last statement only — full multi-char line.
run_case puts_long 'puts("ABCDEFGHIJKLMNOP")' "ABCDEFGHIJKLMNOP"

# Interpolated int as the final write (was "v=").
run_case interp 'v = 42
puts("v=#{v}")' "v=42"

# explicit exit path still correct.
run_case exit_path 'puts("done")
exit(0)' "done"

if [[ $fail -eq 0 ]]; then
  echo "reproduced: all main-exit flush cases produce full output"
  exit 0
else
  echo "NOT FIXED: last-write truncation still present"
  exit 1
fi
