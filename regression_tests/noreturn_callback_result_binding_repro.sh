#!/usr/bin/env bash
# Regression: a callback that never completes normally binds its free result
# variable to NoReturn.
#
# `ENV.fetch(key) : String` calls `fetch(key) { raise KeyError... }` against
# `fetch(key, &block : String -> T) : String | T forall T`. Crystal types the
# raising block as NoReturn, so `T = NoReturn` and the call returns String.
# Inline lowering published callback output only from completing edges, left
# `T` unbound and failed with "cannot establish source return contract
# String | T" for `ENV["HOME"]`, `ENV.fetch("HOME")` and any user method of
# the same shape whose block raises or breaks.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/noreturn-callback-binding.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
def fe(key : String, &block : String -> T) : String | T forall T
  if key.size > 2
    key
  else
    yield key
  end
end

def fp(key : String, &block : String -> T) : String | T forall T
  key.size > 2 ? key : block.call(key)
end

def g(key) : String
  fe(key) { raise "missing #{key}" }
end

STDERR.puts g("abc").size
x = fe("abcd") { raise "x" }
STDERR.puts typeof(x)
STDERR.puts x.size
c = fe("ab") { |k| k.size > 0 ? (break 9) : 2 }
STDERR.puts c
d = fe("ab") { |k| break 10 }
STDERR.puts d
STDERR.puts ENV["HOME"].empty?
STDERR.puts ENV.fetch("HOME").empty?
e = begin
  fe("ab") { |k| raise "short #{k}" }
rescue ex
  ex.message
end
STDERR.puts e
f = fp("abcde") { |k| raise "p #{k}" }
STDERR.puts f.size
CR

expected='3
String
4
9
10
false
false
short ab
5'

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

echo "PASS: a never-completing callback binds its result variable to NoReturn"
