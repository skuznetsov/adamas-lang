#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_macro_inactive_require.XXXXXX")"
SRC="$TMP_DIR/main.cr"
OUT="$TMP_DIR/repro.o"
STDOUT_LOG="$TMP_DIR/stdout.log"
STDERR_LOG="$TMP_DIR/stderr.log"
COMBINED_LOG="$TMP_DIR/combined.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
{% if flag?(:win32) %}
require "crystal/system/windows"
{% else %}
1
{% end %}
CR

set +e
ADAMAS_STOP_AFTER_PARSE=1 \
ADAMAS_PARSE_TRACE=1 \
"$COMPILER" "$SRC" --emit hir --no-prelude --no-ast-cache --verbose -o "$OUT" >"$STDOUT_LOG" 2>"$STDERR_LOG"
compile_status=$?
set -e

cat "$STDOUT_LOG" "$STDERR_LOG" >"$COMBINED_LOG"

echo "compiler: $COMPILER"
echo "status: $compile_status"

main_reqscan="$(grep -F '[REQSCAN_DONE]' "$COMBINED_LOG" | grep -F '/main.cr' | tail -n 1 || true)"
if [[ -n "$main_reqscan" ]]; then
  echo "main_reqscan: $main_reqscan"
fi

fallback_line="$(grep -F 'Source require fallback entries=' "$COMBINED_LOG" | head -n 1 || true)"
if [[ -n "$fallback_line" ]]; then
  echo "fallback_line: $fallback_line"
fi

windows_parse_line="$(grep -F '[PARSE] ' "$COMBINED_LOG" | grep -F '/src/stdlib/crystal/system/windows.cr' | head -n 1 || true)"
if [[ -n "$windows_parse_line" ]]; then
  echo "windows_parse: present"
fi

if [[ $compile_status -eq 0 ]] && grep -Fq 'main.cr reqs=0' "$COMBINED_LOG" && [[ -z "$fallback_line" ]] && [[ -z "$windows_parse_line" ]]; then
  echo "not reproduced: inactive macro require stayed pruned during source fallback"
  exit 1
fi

if [[ -n "$fallback_line" ]] && [[ -n "$windows_parse_line" ]]; then
  echo "reproduced: source fallback reloaded inactive macro require from win32 branch"
  exit 0
fi

if [[ $compile_status -eq 138 || $compile_status -eq 139 ]] && grep -Fq 'main.cr reqs=0' "$COMBINED_LOG" && [[ -n "$windows_parse_line" ]]; then
  echo "reproduced: inactive macro require escaped AST scan and crashed in fallback-loaded windows branch"
  exit 0
fi

echo "reproduced: unexpected failure signature"
echo "--- stdout ---"
cat "$STDOUT_LOG"
echo "--- stderr ---"
cat "$STDERR_LOG"
exit 0
