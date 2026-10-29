#!/usr/bin/env bash
# Inside a `wrap do ... end` block that is inlined, `xs.each_with_index`
# targets `Array(Int32)#each_with_index$Int32`, whose Def lives in Iterable.
# The yield-free check looked the Def up only under the target name, refused
# to lower it for its return type and the member access took the name-shaped
# Pointer guess, so stage 2 failed with "no overload matches
# generic_param_type_name_from_ref for argument types (Pointer)".
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inline-yield-include-origin-return.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/t.cr" <<'CR'
def wrap(&)
  yield
end

def name_of(r : Int32) : String
  "i#{r}"
end

def name_of(r : String) : String
  "s#{r}"
end

def bare(xs : Array(Int32)) : Bool
  r = false
  wrap do
    r = xs.each_with_index.all? { |a, i| name_of(a).size > i }
  end
  r
end

def parens(xs : Array(Int32)) : Bool
  r = false
  wrap do
    e = xs.each_with_index(0)
    r = e.all? { |a, i| name_of(a).size > i }
  end
  r
end

def local_type(xs : Array(Int32)) : String
  s = ""
  wrap do
    e = xs.each_with_index
    s = typeof(e).to_s
  end
  s
end

STDERR.puts bare([1, 2])
STDERR.puts parens([1, 2])
STDERR.puts local_type([1, 2])
CR

printf '%s\n' true true 'Iterator::WithIndexIterator(Indexable::ItemIterator(Array(Int32), Int32), Int32, Int32)' > "$WORK_DIR/want"

stderr_of() {
  awk '/^=== STDERR ===$/ { on = 1; next } /^\[EXIT: / { on = 0 } on' "$1"
}

if [[ -n "$CRYSTAL_BIN" ]]; then
  if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build "$WORK_DIR/t.cr" \
      -o "$WORK_DIR/t.orig" > "$WORK_DIR/orig.log" 2>&1; then
    printf 'ORACLE FAIL: original rejects the program\n' >&2
    cat "$WORK_DIR/orig.log" >&2
    exit 2
  fi
  "$SAFE_RUNNER" "$WORK_DIR/t.orig" 5 256 > "$WORK_DIR/orig.run" 2>&1 || true
  if ! stderr_of "$WORK_DIR/orig.run" | diff -u "$WORK_DIR/want" - >&2; then
    printf 'ORACLE FAIL: original output differs\n' >&2
    exit 2
  fi
fi

"$SAFE_RUNNER" "$ADAMAS_BIN" 600 8192 "$WORK_DIR/t.cr" -o "$WORK_DIR/t.adamas" \
  > "$WORK_DIR/adamas.log" 2>&1 || true
if [[ ! -x "$WORK_DIR/t.adamas" ]]; then
  printf 'FAIL: compile failed\n' >&2
  grep -m3 -a 'rror' "$WORK_DIR/adamas.log" >&2 || tail -5 "$WORK_DIR/adamas.log" >&2
  exit 1
fi
"$SAFE_RUNNER" "$WORK_DIR/t.adamas" 5 256 > "$WORK_DIR/adamas.run" 2>&1 || true
if ! stderr_of "$WORK_DIR/adamas.run" | diff -u "$WORK_DIR/want" - >&2; then
  printf 'FAIL: output differs from original Crystal\n' >&2
  exit 1
fi
printf 'PASS include-origin return inside an inline block\n'
