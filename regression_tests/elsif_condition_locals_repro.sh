#!/usr/bin/env bash
# An elsif test runs on the false edge of the previous test, so an
# assignment in an earlier elsif condition is visible to the later tests,
# their bodies, the else and the code after the `if`. V2 restored the locals
# of the state before the whole chain for every elsif test and the else:
# `elsif (x = nil) ... elsif x` still read the old `x`, took the wrong
# branch, and a variable first assigned in an elsif condition was undefined
# in the else. Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/elsif-condition-locals.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def no(v) : Bool
  false
end

def yes(v) : Bool
  true
end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# name:expected-exit
CASES=()

add_case() {
  CASES+=("$1:$2")
  write_case "$1" "$3"
}

add_case nil_assignment_rebinds_later_test 30 '
def run(flag : Bool) : Int32
  x = 2
  if flag
    10
  elsif (x = nil)
    11
  elsif x
    x &+ 20
  else
    30
  end
end
LibC.exit(run(false))'

add_case new_variable_visible_in_else 10 '
def run(flag : Bool) : Int32
  if flag
    1
  elsif no(y = 7)
    2
  else
    y &+ 3
  end
end
LibC.exit(run(false))'

add_case assignment_visible_in_later_test_body 45 '
def run(flag : Bool) : Int32
  x = 1
  if flag
    2
  elsif no(x = 5)
    3
  elsif yes(x)
    x &+ 40
  else
    0
  end
end
LibC.exit(run(false))'

add_case assignment_visible_after_if 16 '
def run(flag : Bool) : Int32
  x = 1
  if flag
    0
  elsif no(x = 6)
    0
  else
    0
  end
  x
end
LibC.exit(run(false) &+ run(true) &* 10)'

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}" want="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$want" ]]; then
      printf 'ORACLE FAIL: original %s exited %s, not %s\n' "$name" \
        "$(exit_code_of "$WORK_DIR/$name.orig.run")" "$want" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}" want="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  got="$(exit_code_of "$run_log")"
  if [[ "$got" == "$want" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: exit %s, expected %s\n' "$name" "$got" "$want" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d elsif condition locals case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all elsif condition locals cases passed\n'
