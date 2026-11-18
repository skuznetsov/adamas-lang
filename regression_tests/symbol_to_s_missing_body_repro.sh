#!/usr/bin/env bash
# Regression: Symbol#to_s must read the symbol table, not abort.
#
# Symbol#to_s is a bodyless `@[Primitive(:symbol_to_s)]` declaration. HIR has
# no intrinsic for it and keeps the call, and HIR stopped materializing
# bodyless primitive declarations, so the callee reached LLVM emission only as
# a missing function. The backend's symbol-table body was attached to the
# ordinary-function path alone, so every Symbol#to_s/inspect (direct, through
# a union arm, or from Symbol#inspect) linked to a `STUB CALLED:
# Symbol$Hto_s` abort stub. The missing-body path now emits the same lookup.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/symbol-to-s.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
def pick(k)
  v = 0
  if k == 0
    v = "arg"
  elsif k == 1
    v = :key
  end
  v
end

STDERR.puts :key.to_s
STDERR.puts :key.inspect
STDERR.puts :"two words".inspect
STDERR.puts :"two words".to_s.size
STDERR.puts (:abc <=> :abd)
STDERR.puts (:b > :a)
b = [0, :key]
STDERR.puts b[1].to_s
STDERR.puts b[1].inspect
v = ARGV.empty? ? :left : "right"
STDERR.puts v.inspect
STDERR.puts pick(0).inspect
STDERR.puts pick(1).inspect
STDERR.puts pick(2).inspect
CR

expected='key
:key
:"two words"
9
-1
true
key
:key
:left
"arg"
:key
0'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: symbol program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: symbol program exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

expected_string_arm='key
:key
:"two words"
9
-1
true
key
:key
"right"
"arg"
:key
0'

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 use-string-arm 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected_string_arm" ]]; then
  echo "FAIL: non-Symbol union arm exit=$status" >&2
  diff <(printf '%s\n' "$expected_string_arm") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: Symbol#to_s reads the symbol table"
