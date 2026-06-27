#!/usr/bin/env bash
# Regression: an escaped interpolation opener inside a string literal must not
# put the lexer into interpolation mode and swallow the rest of the class body.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2-escaped-interp.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/parse.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
class Box
  def a
    if current_char == '{'
      io << "\\\#{"
    else
      io << '#'
    end
  end

  def tail
    7
  end
end
CR

set +e
ADAMAS_STOP_AFTER_PARSE=1 \
ADAMAS_TRACE_STDERR=1 \
ADAMAS_TRACE_PARSED_CLASS=Box \
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 "$SRC" --no-prelude -o "$OUT" >"$LOG" 2>&1
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "FAIL: parser stop-after-parse run failed (status $status)" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

if ! grep -q 'key=class_body .* b=2' "$LOG"; then
  echo "FAIL: Box class body was not parsed as two members" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

echo "stage2_escaped_interpolation_string_parser_ok"
