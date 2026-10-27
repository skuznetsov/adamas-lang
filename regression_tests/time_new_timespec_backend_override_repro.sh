#!/usr/bin/env bash
# `Time.new(LibC::Timespec, Time::Location)` must lower its stdlib body.
#
# The LLVM backend replaced that function with a hand-written body that
# called `@Time$Dnew$$Int64`, a function that no longer exists, and dropped
# the nanoseconds and the location. llc rejected every program that reached
# it ("use of undefined value '@Time$Dnew$$Int64'"), e.g. through
# File::Info#modification_time in File.tempname. The stdlib body
# (time.cr) now lowers like any other constructor.
# Needs the prelude (the override keyed on the mangled stdlib name).
# Exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/time-new-timespec.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/time_new.cr" <<'CR'
ts = LibC::Timespec.new
ts.tv_sec = 5
ts.tv_nsec = 7
t = Time.new(ts, Time::Location::UTC)
code = 0
code += 10 if t.to_unix == 5
code += 20 if t.nanosecond == 7
code += 12 if t.utc?
exit(code)
CR

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

if [[ -n "$CRYSTAL_BIN" ]]; then
  if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build "$WORK_DIR/time_new.cr" \
      -o "$WORK_DIR/time_new.orig" > "$WORK_DIR/orig.log" 2>&1; then
    echo "ORACLE FAIL: original rejects time_new" >&2
    cat "$WORK_DIR/orig.log" >&2
    exit 2
  fi
  "$SAFE_RUNNER" "$WORK_DIR/time_new.orig" 5 256 > "$WORK_DIR/orig.run" 2>&1 || true
  if [[ "$(exit_code_of "$WORK_DIR/orig.run")" != "42" ]]; then
    echo "ORACLE FAIL: original time_new did not exit 42" >&2
    exit 2
  fi
fi

"$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/time_new.cr" -o "$WORK_DIR/time_new" \
  > "$WORK_DIR/build.log" 2>&1 || true
if [[ "$(exit_code_of "$WORK_DIR/build.log")" != "0" || ! -x "$WORK_DIR/time_new" ]]; then
  echo "FAIL time_new: compile failed" >&2
  grep -a 'error' "$WORK_DIR/build.log" | head -3 >&2 || tail -3 "$WORK_DIR/build.log" >&2
  exit 1
fi
"$SAFE_RUNNER" "$WORK_DIR/time_new" 5 256 > "$WORK_DIR/run.log" 2>&1 || true
got="$(exit_code_of "$WORK_DIR/run.log")"
if [[ "$got" != "42" ]]; then
  echo "FAIL time_new: exit $got, expected 42" >&2
  exit 1
fi
echo "PASS time_new_timespec_backend_override"
