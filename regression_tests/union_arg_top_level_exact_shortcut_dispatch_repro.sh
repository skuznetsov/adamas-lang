#!/usr/bin/env bash
# Regression: a top-level bare call with a union argument dispatches per arm
# even when a symbol named after the whole union already exists.
#
# The early top-level shortcut emits a direct call when
# `mangle(name, arg_types)` is registered and the source resolver picks that
# declaration for the whole union. A union argument is split across
# overloads instead. With `h(x : String)` beside `h(x : Int32 | String)`,
# String values run the String overload. The shortcut sent every value to
# `h$Int32 | String`. For `fv(x : T) forall T` and `g(x)`, the first call
# dispatched correctly but registered the whole-union instantiation, so a
# second call with the same union type took the shortcut and String values
# reached the free-variable body. The shortcut now applies only when every
# variant resolves to the same declaration. Expected output is checked
# against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-arg-top-level-shortcut.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
def fv(s : String) : String
  "FS(#{s})"
end

def fv(x : T) : String forall T
  "FT(#{x}:#{typeof(x)})"
end

def h(x : String) : String
  "HS(#{x})"
end

def h(x : Int32 | String) : String
  "HU(#{x}:#{typeof(x)})"
end

def n(x : Nil) : String
  "NN"
end

def n(x : Int32?) : String
  "NI(#{x})"
end

def g(x : Char) : String
  "GC(#{x})"
end

def g(x) : String
  "GO(#{x}:#{typeof(x)})"
end

def one(x) : String
  "ONE(#{x}:#{typeof(x)})"
end

z = ARGV.size > 5 ? "s" : 2
y = ARGV.size > 5 ? 4 : "t"
STDERR.puts fv(z)
STDERR.puts fv(y)
STDERR.puts h(y)
STDERR.puts h(z)
STDERR.puts h(y)
w = ARGV.size > 5 ? 3 : nil
v = ARGV.size > 5 ? nil : 5
STDERR.puts n(v)
STDERR.puts n(w)
c = ARGV.size > 5 ? 1_i64 : 'q'
d = ARGV.size > 5 ? 'r' : 8_i64
STDERR.puts g(d)
STDERR.puts g(c)
STDERR.puts g(d)
STDERR.puts one(z)
STDERR.puts one(y)
CR

expected='FT(2:(Int32 | String))
FS(t)
HS(t)
HU(2:(Int32 | String))
HS(t)
NI(5)
NN
GO(8:(Char | Int64))
GC(q)
GO(8:(Char | Int64))
ONE(2:(Int32 | String))
ONE(t:(Int32 | String))'
strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH\|run_safe\.sh: ' || true; }

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

echo "PASS: a top-level union-argument call dispatches per arm despite an exact union symbol"
