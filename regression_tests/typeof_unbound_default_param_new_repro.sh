#!/usr/bin/env bash
# `W(typeof(o)).new(o)` in `def a(o : Int = 0)` names `W(Int32)` for a call
# that omits the argument. Return inference without a callsite left `o`
# unbound, spliced the "Pointer(Void)" typeof sentinel into the type name and
# fixed the return type to `W(Pointer(Void))`, so `x.a.o` read a pointer.
# Stage 2 failed the same way on `each_with_index` (WithIndexIterator(...,
# typeof(offset))): "no overload matches ... for argument types (Pointer)".
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typeof-unbound-default-param-new.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/t.cr" <<'CR'
class W(O)
  def initialize(@o : O)
  end

  def o
    @o
  end
end

class Bx
  def a(o : Int = 0)
    W(typeof(o)).new(o)
  end

  def b(o = 0)
    W(typeof(o)).new(o)
  end
end

x = Bx.new
STDERR.puts typeof(x.a(1_i64))
STDERR.puts typeof(x.b(1_i64))
STDERR.puts typeof(x.a(2))
STDERR.puts x.a(1_i64).o
STDERR.puts x.a.o
STDERR.puts x.b.o + 7
STDERR.puts x.a.class.name
CR

printf '%s\n' 'W(Int64)' 'W(Int64)' 'W(Int32)' 1 0 7 'W(Int32)' > "$WORK_DIR/want"

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
printf 'PASS typeof of an unbound default parameter\n'
