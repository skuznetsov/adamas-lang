#!/usr/bin/env bash
# `line(1)` materializes `line$Int32_Nil | Int32` for the defaulted nilable
# param; a later `line(1, v)` requests `line$Int32_Int32`. Top-level def
# materialization emitted under the requested name but keyed completeness on
# the resolved target, so the second request returned early and the call
# site kept an undefined symbol (STUB).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/default_arg_specialization_after_union_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
def line(a : Int32, c : Int32? = nil) : Nil
  STDERR.puts "#{a} #{c}"
end

line(1)
v = 5
line(1, v)
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if grep -n "STUB" "$WORK_DIR/build.log" >&2; then
  echo "FAIL: call site left with a stubbed specialization" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
printf '1 \n1 5\n' >"$WORK_DIR/expected"
grep -E '^1( |$)' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: default-arg specialization after nilable sibling" >&2
  exit 1
fi
echo "PASS: distinct default-arg specialization is materialized"
