#!/usr/bin/env bash
# Regression: an unresolved call must not bind to a sole overload that needs
# more arguments than the call supplies.
#
# MIR call lowering falls back to the only function in a method family when
# the exact target is missing. The fallback ignored arity, so the bodyless
# primitive `Symbol#to_s` bound to its only materialized sibling
# `Symbol#to_s$IO` (padding the missing IO with null). That body is
# `io << to_s`, so `:sym.to_s(io)` recursed into itself until the stack ran out
# (SIGILL). The sole fallback now requires the callee to accept the call's
# arguments; otherwise the call stays unresolved and the missing-body path
# emits the primitive.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sole-overload-arity.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Only the IO overload of Symbol#to_s is reachable from source here.
cat > "$WORK_DIR/m.cr" <<'CR'
io = IO::Memory.new
:written.to_s(io)
io << ' '
:"two words".to_s(io)
STDERR.puts io.to_s
CR

expected='written two words'

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
  echo "FAIL: exit=$status output=$(printf '%s' "$printed" | head -3)" >&2
  exit 1
fi

echo "PASS: sole overload fallback respects arity"
