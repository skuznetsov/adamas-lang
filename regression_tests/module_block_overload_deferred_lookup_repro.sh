#!/usr/bin/env bash
# Regression: demanded `Owner#method$block` must materialize from the included
# module's block-taking def during the deferred module lookup.
#
# `Set(String)#first` (Enumerable#first : T) calls `first { raise EmptyError }`.
# The demanded target `Set(String)#first$block` reached the deferred module
# lookup with expected_param_count pulled from the callsite record, which
# counts the materialized block proc as a positional arg type. `def first(&)`
# has zero positional params, so the arity check rejected it, the wrapper was
# never lowered, and the repair pass rewrote the call to the no-block sibling:
# Set(String)#first called ITSELF until stack overflow (SIGBUS).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module_block_overload.XXXXXX")"
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
s = Set(String).new
s << "hello"
# no-block first : T -> first { raise Enumerable::EmptyError.new } internally
puts s.first
# sibling shapes that were already healthy - keep them that way
puts s.first? || "none"
puts s.first { "empty" }
CR

"$COMPILER" "$SRC" -o "$OUT" >"$LOG" 2>&1 || {
  echo "compile failed" >&2
  tail -40 "$LOG" >&2
  exit 1
}

ACTUAL="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED="$(printf 'hello\nhello\nhello')"

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "FAIL: output mismatch (self-recursive Set#first regression?)" >&2
  echo "--- expected ---" >&2
  echo "$EXPECTED" >&2
  echo "--- actual ---" >&2
  echo "$ACTUAL" >&2
  exit 1
fi

echo "OK: module block-overload materializes via deferred lookup (Set#first)"
