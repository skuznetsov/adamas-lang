#!/usr/bin/env bash
# A proc literal sent to a C function must not be a closure. A constant
# receiver (`GC.lock_write`) was taken for an implicit self call, so `self` was
# captured and the plain proc was rejected with "can't send closure to C
# function"; prelude hello hits this at boehm.cr
# `LibGC.set_start_callback -> do GC.lock_write end`. A proc that really
# captures a local, or an instance method's `self`, must still be rejected
# exactly as original Crystal does.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-literal-false-self-capture.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# The proc box is still heap-allocated, so no-prelude fixtures link libgc.
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

module M
  def self.hit : Nil
    LibC._exit(7)
  end
end
'

write_case() {
  printf '%s\n%s\n' "$PRELUDE" "$2" > "$WORK_DIR/$1.cr"
}

write_case class_method_constant_receiver '
module N
  def self.init : Nil
    LibC.atexit -> do
      M.hit
    end
  end
end
N.init
LibC.exit(9)'

write_case instance_method_constant_receiver '
class C
  def go : Nil
    LibC.atexit -> do
      M.hit
    end
  end
end
C.new.go
LibC.exit(9)'

write_case captured_local '
def go : Nil
  x = 4
  LibC.atexit -> do
    LibC._exit(x)
  end
end
go
LibC.exit(9)'

write_case instance_method_implicit_self '
class C
  def hit : Nil
    LibC._exit(4)
  end

  def go : Nil
    LibC.atexit -> do
      hit
    end
  end
end
C.new.go
LibC.exit(9)'

POSITIVE_CASES=(class_method_constant_receiver:7 instance_method_constant_receiver:7)
NEGATIVE_CASES=(captured_local instance_method_implicit_self)
NEGATIVE_DIAGNOSTIC="can't send closure to C function"

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
  for name in "${NEGATIVE_CASES[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1 ||
        ! grep -qF "$NEGATIVE_DIAGNOSTIC" "$WORK_DIR/$name.orig.log"; then
      printf 'ORACLE FAIL: original does not reject %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
  done
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

for name in "${NEGATIVE_CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "1" ]] && grep -qF "$NEGATIVE_DIAGNOSTIC" "$log" &&
      [[ ! -e "$WORK_DIR/$name.adamas" ]]; then
    printf 'PASS negative %s\n' "$name"
  else
    printf 'FAIL negative %s (exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d proc-literal self-capture case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'proc-literal false self-capture cases passed\n'
