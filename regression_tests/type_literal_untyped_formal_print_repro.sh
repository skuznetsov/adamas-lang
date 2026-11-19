#!/usr/bin/env bash
# Regression: a type literal passed to an untyped IO formal prints its name.
#
# A type object and its instances share one ABI TypeRef, so the call symbol
# carries the source kind (`IO#puts$Int32.class`). Two producers dropped it:
#   - `io << T` is lowered by the binary-operator path, which mangled the
#     instance key `IO#<<$Int32` and printed the zero instance carrier ("0");
#   - receiver repair re-keyed inherited calls inside virtual copies
#     (`IO::FileDescriptor#puts$Int32.class` -> `IO#<<$Int32`) from TypeRefs
#     alone, so `STDERR.puts Int32` printed "0" and `STDERR.puts Nil` an
#     empty line.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/type-literal-print.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
def show(x)
  STDERR << x
  STDERR.print "\n"
end

def say(x)
  STDERR.puts x
end

STDERR.puts Int32
STDERR.puts Nil
STDERR << String
STDERR.print "\n"
STDERR.print Float64
STDERR.print "\n"
show(Int32)
show(7)
say(Nil)
say(nil.inspect)
t = Char
say(t)
say('c')
STDERR << Int32 << " " << 42 << "\n"
io = IO::Memory.new
io << Int32 << ":" << Nil
io.print Bool
STDERR.puts io.to_s
STDERR.puts String.build { |b| b << Float64 << "/" << 1.5 }
CR

expected='Int32
Nil
String
Float64
Int32
7
Nil
nil
Char
c
Int32 42
Int32:NilBool
Float64/1.5'

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
  if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: exit=$status" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

run_program "$WORK_DIR/m"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: type literals print through untyped IO formals"
