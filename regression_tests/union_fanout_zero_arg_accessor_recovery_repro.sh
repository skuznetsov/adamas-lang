#!/usr/bin/env bash
# Regression: a union-argument fanout arm keeps the arity-1 overload it
# selected when a zero-argument overload of the same method also exists.
#
# `STDERR.puts x` with `x : Int32 | String` fans out per arm; the Int32 arm
# resolves to `IO#puts$arity1` (the untyped `puts(obj : _)` def) and is
# lowered by name, without call-site argument types. The direct-accessor
# recovery in lower_function_if_needed treated "no argument types" as a
# zero-argument call and swapped in the zero-argument `def puts : Nil`
# (recorded as the getter/def winner for `puts`). lower_method then rejected
# the mismatch with "method body target already has a different source
# definition: IO#puts$arity1". The recovery now applies only when the
# selected def itself has the zero-argument call shape. The direct
# `STDERR.puts 5` is the control; the second union checks the other arm order.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-fanout-accessor.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/u.cr" <<'CR'
STDERR.puts 5
x = ARGV.size > 5 ? 1 : "s"
STDERR.puts x
y = ARGV.size > 5 ? "t" : 3
STDERR.puts y
CR

expected='5
s
3'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/u.cr" -o "$WORK_DIR/u_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/u_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/u.cr" -o "$WORK_DIR/u" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/u" ]]; then
  echo "FAIL: union fanout program did not compile" >&2
  strip < "$WORK_DIR/build.log" | tail -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/u" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi
echo "PASS union_fanout_zero_arg_accessor_recovery"
