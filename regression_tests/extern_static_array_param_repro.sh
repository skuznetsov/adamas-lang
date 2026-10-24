#!/usr/bin/env bash
# Lib fun parameters may use Crystal's `T[N]` static-array sugar; LibC declares
# `fun futimens(fd : Int, times : Timespec[2])`, so every full-prelude program
# depends on it. The extern signature validator must read `T[N]` as
# `StaticArray(T, N)` and still reject an undefined element type the way
# original Crystal does (`undefined constant Nope`).
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/extern-static-array-param.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/direct.cr" <<'CR'
lib LibX
  struct Ts
    a : Int64
    b : Int64
  end
  fun futimens(fd : Int32, times : Ts[2]) : Int32
end
x = 1
CR

cat > "$WORK_DIR/alias_and_pointer.cr" <<'CR'
lib LibX
  struct Ts
    a : Int64
    b : Int64
  end
  alias TsA = Ts
  fun futimens(fd : Int32, times : TsA[2]) : Int32
  fun g(x : Int32[4]*) : Int32
end
x = 1
CR

cat > "$WORK_DIR/undefined_element.cr" <<'CR'
lib LibX
  fun futimens(fd : Int32, times : Nope[2]) : Int32
end
x = 1
CR

POSITIVE_CASES=(direct alias_and_pointer)
NEGATIVE_CASES=(undefined_element)
NEGATIVE_DIAGNOSTIC="undefined constant Nope"

failures=0

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE_CASES[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects positive %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
  done
  for name in "${NEGATIVE_CASES[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1 ||
        ! grep -qF "$NEGATIVE_DIAGNOSTIC" "$WORK_DIR/$name.orig.log"; then
      printf 'ORACLE FAIL: original does not reject %s with "%s"\n' "$name" "$NEGATIVE_DIAGNOSTIC" >&2
      exit 2
    fi
  done
fi

for name in "${POSITIVE_CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if grep -q '\[EXIT: 0\]' "$log"; then
    printf 'PASS positive %s\n' "$name"
  else
    printf 'FAIL positive %s: %s\n' "$name" "$(grep -m1 'error' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE_CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if ! grep -q '\[EXIT: 0\]' "$log" && grep -qF "$NEGATIVE_DIAGNOSTIC" "$log" &&
      ! grep -qF "${NEGATIVE_DIAGNOSTIC}[" "$log"; then
    printf 'PASS negative %s\n' "$name"
  else
    printf 'FAIL negative %s: %s\n' "$name" "$(grep -m1 'error' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d extern static-array case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'extern static-array parameter cases passed\n'
