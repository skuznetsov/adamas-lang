#!/usr/bin/env bash
# Regression: a method call on a nilable all-reference union runs Nil's own
# method for the nil arm.
#
# `(Nil | String)` keeps Nil as null and dispatches through the object header;
# the MIR null guard calls Nil's method when one is lowered. HIR lowered the
# targets of every union variant except Nil, so the guard found no Nil#inspect
# and returned null: `x.inspect` handed puts a null String, which crashed in
# String#to_slice and hung in the signal handler. HIR now lowers the Nil target
# whenever Nil defines the method.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nilable-union-nil-arm.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
i = ARGV.size
a = [nil, "n"]
x = a[i]
STDERR.puts x.inspect
STDERR.puts x.to_s.size
STDERR.puts a[i + 1].inspect
y = [nil, "m"][i]
STDERR.puts y.inspect
h = {"k" => "v"}
STDERR.puts h["z"]?.inspect
STDERR.puts h["k"]?.inspect
STDERR.puts "done"
CR

expected='nil
0
"n"
nil
nil
"v"
done'

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

echo "PASS: nilable union nil arm runs Nil methods"
