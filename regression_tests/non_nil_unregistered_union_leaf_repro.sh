#!/usr/bin/env bash
# A nil-removing narrowing (`x.try { |i| ... }`, `if i = x`) registers source
# kind facts for the narrowed SSA value. A union-typed leaf with no registered
# facts (a virtual call result, a raw-callback block call result) used to be
# narrowed into the un-narrowed carrier in both kinds, e.g. `Nil | Int32 |
# Nil.class | Int32.class`. That widened the set past what the general source
# walker reports for the same value and falsely rejected `f(i : Int)`.
# Prelude shape: `Indexable#bsearch` ->
# `bsearch_index { ... }.try { |index| unsafe_fetch(index) }` reached from
# Crystal::DWARF::LineNumbers, which broke prelude hello with the in-repo
# stdlib. A direct call whose lowered body returns `Alpha | Alpha.class | Nil`
# must still be rejected by `Proc(Alpha, Int32)#call` after narrowing.
# Expected outcomes are checked against original Crystal when CRYSTAL_BIN is set.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
FIXTURES="$ROOT_DIR/regression_tests/non_nil_unregistered_union_leaf"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/non-nil-union-leaf.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# name expected-exit (or "reject")
CASES=(
  "virtual_try 30"
  "virtual_if_guard 47"
  "reject_direct_mixed_kind reject"
)

fail=0
for entry in "${CASES[@]}"; do
  read -r name want <<<"$entry"
  src="$FIXTURES/$name.cr"

  if [[ -n "$CRYSTAL_BIN" ]]; then
    if "$CRYSTAL_BIN" build --prelude=empty "$src" -o "$WORK_DIR/$name.orig" >"$WORK_DIR/$name.orig.log" 2>&1; then
      orig_out="$("$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 2>&1 || true)"
      orig_exit="$(printf '%s\n' "$orig_out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1)"
      orig="$orig_exit"
    else
      orig="reject"
    fi
    if [[ "$orig" != "$want" ]]; then
      echo "ORACLE_MISMATCH $name: original=$orig expected=$want"
      fail=1
      continue
    fi
  fi

  if "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$src" -o "$WORK_DIR/$name.bin" >"$WORK_DIR/$name.log" 2>&1 &&
     [[ -x "$WORK_DIR/$name.bin" ]]; then
    out="$("$SAFE_RUNNER" "$WORK_DIR/$name.bin" 5 256 2>&1 || true)"
    got="$(printf '%s\n' "$out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1)"
  else
    if grep -aq "no overload matches" "$WORK_DIR/$name.log"; then
      got="reject"
    else
      got="compile-failure"
      sed -n '1,8p' "$WORK_DIR/$name.log"
    fi
  fi

  if [[ "$got" == "$want" ]]; then
    echo "PASS $name"
  else
    echo "FAIL $name: expected $want, got $got"
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo "non-nil unregistered union leaf regression failed"
  exit 1
fi
echo "non-nil unregistered union leaf regression passed"
