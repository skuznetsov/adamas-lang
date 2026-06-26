#!/usr/bin/env bash
# Regression: produced s2b must resolve full-prelude wildcard requires such as
# stdlib/indexable.cr's `require "./indexable/*"` without falling into the
# source-fallback Dir.glob path that raises "Unreachable" in self-hosted builds.
#
# This is a focused frontier guard, not a full s2b readiness test: later
# compiler phases may still fail while this require-resolution contract stays
# fixed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_full_prelude_wildcard.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/puts42.cr"
OUT="$TMP_DIR/puts42"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
puts 42
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 "$SRC" --verbose -o "$OUT" >"$LOG" 2>&1
status=$?
set -e

if grep -Fq "error: Unreachable" "$LOG"; then
  echo "FAIL: full-prelude wildcard require fell through to Unreachable" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

if grep -Fq "Warning: Could not resolve require './indexable/*'" "$LOG"; then
  echo "FAIL: ./indexable/* was not resolved by the primary wildcard resolver" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

if ! grep -Fq "[req-resolved] glob count=1" "$LOG" || ! grep -Fq "src/stdlib/indexable/mutable.cr" "$LOG"; then
  echo "FAIL: ./indexable/* did not resolve to indexable/mutable.cr" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

echo "stage2_full_prelude_wildcard_require_ok status=$status"
