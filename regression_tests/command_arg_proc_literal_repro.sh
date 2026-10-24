#!/usr/bin/env bash
# Crystal starts a command-call argument at `->`, so a proc literal passed
# without parentheses (`LibGC.set_start_callback -> do ... end` in the prelude)
# is the call's argument. The parser rejected `->` as an argument start for
# every callee (meant only for `[] of A -> ...` proc type notation), so the
# proc became a separate statement and the lib fun call had zero arguments
# ("wrong number of arguments for 'LibGC.set_start_callback'"). Each fixture's
# callback `_exit`s from the atexit handler, so the exit code proves that the
# proc reached the call. A genuinely argument-less call must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/command-arg-proc-literal.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Adamas still boxes a proc literal on the managed heap (even a non-capturing
# one passed straight to C), so the no-prelude fixtures link libgc themselves.
PRELUDE='@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun atexit(callback : ->) : Int32
  fun exit(status : Int32) : NoReturn
  fun _exit(status : Int32) : NoReturn
end

def raise(message)
  LibC.exit(3)
end

def reg(callback)
  LibC.atexit(callback)
end
'

{ printf '%s\n' "$PRELUDE"; cat <<'CR'
LibC.atexit -> do
  LibC._exit(7)
end
LibC.exit(9)
CR
} > "$WORK_DIR/lib_fun_do_body.cr"

{ printf '%s\n' "$PRELUDE"; cat <<'CR'
LibC.atexit -> { LibC._exit(6) }
LibC.exit(9)
CR
} > "$WORK_DIR/lib_fun_brace_body.cr"

{ printf '%s\n' "$PRELUDE"; cat <<'CR'
reg -> do
  LibC._exit(5)
end
LibC.exit(9)
CR
} > "$WORK_DIR/receiverless_def_do_body.cr"

{ printf '%s\n' "$PRELUDE"; cat <<'CR'
LibC.atexit
LibC.exit(9)
CR
} > "$WORK_DIR/missing_argument.cr"

POSITIVE_CASES=(lib_fun_do_body:7 lib_fun_brace_body:6 receiverless_def_do_body:5)
NEGATIVE_CASE=missing_argument
NEGATIVE_DIAGNOSTIC="atexit' (given 0, expected 1)"

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${POSITIVE_CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
      "$WORK_DIR/$NEGATIVE_CASE.cr" -o "$WORK_DIR/$NEGATIVE_CASE.orig" > "$WORK_DIR/$NEGATIVE_CASE.orig.log" 2>&1 ||
      ! grep -qF "$NEGATIVE_DIAGNOSTIC" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
    printf 'ORACLE FAIL: original does not reject %s\n' "$NEGATIVE_CASE" >&2
    exit 2
  fi
fi

failures=0

for entry in "${POSITIVE_CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL positive %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS positive %s\n' "$name"
  else
    printf 'FAIL positive %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

log="$WORK_DIR/$NEGATIVE_CASE.adamas.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$NEGATIVE_CASE.cr" \
  -o "$WORK_DIR/$NEGATIVE_CASE.adamas" > "$log" 2>&1 || true
if [[ "$(exit_code_of "$log")" == "1" ]] && grep -qF "$NEGATIVE_DIAGNOSTIC" "$log" &&
    [[ ! -e "$WORK_DIR/$NEGATIVE_CASE.adamas" ]]; then
  printf 'PASS negative %s\n' "$NEGATIVE_CASE"
else
  printf 'FAIL negative %s (exit %s): %s\n' "$NEGATIVE_CASE" "$(exit_code_of "$log")" \
    "$(grep -m1 -i 'error' "$log" || tail -1 "$log")"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d command-argument proc literal case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'command-argument proc literal cases passed\n'
