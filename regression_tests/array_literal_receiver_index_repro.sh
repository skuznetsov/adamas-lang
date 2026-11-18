#!/usr/bin/env bash
# Regression: indexing an array literal directly reads elements of its type.
#
# `lower_index` had an array-literal shortcut that always typed the IndexGet
# result as Int32. A literal of union, String, or Float elements was read with
# the Int32 width: `[7, "arg"][i]` printed the union type id, `["a", "b"][i]`
# printed a pointer as an integer, and `k.is_a?(String)` on the element was
# always false. Assigning the literal to a local first took the typed-array
# path and worked. A literal typed as Array(T) now uses that same path.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array-literal-index.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
i = ARGV.size
STDERR.puts [7, "arg", :key][i].inspect
STDERR.puts [7, "arg", :key][i + 1].inspect
STDERR.puts [7, "arg", :key][i + 2].inspect
STDERR.puts ["a", "b"][i + 1]
STDERR.puts [1.5, 2.5][i + 1]
STDERR.puts [10, 20, 30][1..2].inspect
STDERR.puts [10, 20, 30][i + 2]
k = [7, "arg"][i + 1]
STDERR.puts k.is_a?(String) ? "str #{k.size}" : "int"
STDERR.puts({1 => [3, 4][i + 1]}[1])
CR

expected='7
"arg"
:key
b
2.5
[20, 30]
30
str 3
4'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: array literal receivers index with their element type"
