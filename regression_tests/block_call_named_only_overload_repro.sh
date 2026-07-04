#!/usr/bin/env bash
# Regression: block-call overload selection must reject candidates with
# REQUIRED named-only params when the call passes no named args.
# Before the fix, `[1,2,3].find { |v| v > 2 }` inlined
# Indexable#find(if_none = nil, *, offset : Int, &) — the required named-only
# `offset` was never bound, lowered as an uninitialized VOID local, and fed
# garbage loop bounds (printed -1 instead of 3). Same family through
# lookup_block_function_def_for_call for `find(-1) { }` (positional if_none).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block_call_named_only_overload.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
# A: 0-arg find with block — must pick Enumerable#find(if_none = nil, &),
# NOT Indexable#find(if_none = nil, *, offset : Int, &) (was: garbage -1)
puts [1, 2, 3].find { |v| v > 2 } || -1

# B: positional if_none, no match — must return the if_none value (was: garbage)
puts [1, 2, 3].find(-1) { |v| v > 8 } || -99

# C: positional if_none, match — must return the found element (was: garbage)
puts [1, 2, 3].find(-1) { |v| v > 1 } || -99

# D: negative — no match without if_none stays nil
puts [1, 2, 3].find { |v| v > 9 } || -1

# E: any? on the same include chain still works
puts [1, 2, 3].any? { |v| v > 5 }
CR

"$COMPILER" "$SRC" -o "$OUT" >"$LOG" 2>&1 || {
  echo "compile failed" >&2
  tail -40 "$LOG" >&2
  exit 1
}

ACTUAL="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED="$(printf '3\n-1\n2\n-1\nfalse')"

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "FAIL: block-call selected an overload with required named-only params" >&2
  echo "--- expected ---" >&2
  echo "$EXPECTED" >&2
  echo "--- actual ---" >&2
  echo "$ACTUAL" >&2
  exit 1
fi

echo "OK: block calls skip overloads with required named-only params (find picks Enumerable)"
