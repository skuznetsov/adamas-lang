#!/usr/bin/env bash
# B3 contract guard: language-behavior changes need an original-vs-stage
# semantic oracle, not only stage1-vs-generated-stage agreement.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-crystal}"
TIMEOUT_SECS="${ORIGINAL_STAGE_ORACLE_TIMEOUT:-5}"
MAX_MEM_MB="${ORIGINAL_STAGE_ORACLE_MAX_MEM:-512}"
EXPECT_MISMATCH="${ADAMAS_EXPECT_ORIGINAL_STAGE_MISMATCH:-0}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi
if ! command -v "$ORIGINAL_CRYSTAL" >/dev/null 2>&1; then
  echo "ERROR: original Crystal compiler not found: $ORIGINAL_CRYSTAL" >&2
  exit 2
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/original_vs_stage_semantic_oracle.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

SRC="$WORKDIR/oracle.cr"
ORIGINAL_BIN="$WORKDIR/original_bin"
STAGE_BIN="$WORKDIR/stage_bin"
ORIGINAL_RUN_LOG="$WORKDIR/original.run.log"
STAGE_RUN_LOG="$WORKDIR/stage.run.log"
ORIGINAL_STDOUT="$WORKDIR/original.stdout"
STAGE_STDOUT="$WORKDIR/stage.stdout"
STAGE_COMPILE_LOG="$WORKDIR/stage.compile.log"

cat >"$SRC" <<'CRYSTAL'
puts "TYPE=#{typeof([1, 2, 3][0])}"
puts "CONST=#{1 + 2 * 3}"
puts "UNION=#{(true ? 1 : nil).class}"
CRYSTAL

extract_run_safe_stdout() {
  local input="$1"
  local output="$2"
  awk '
    /^=== STDOUT ===$/ { in_stdout = 1; next }
    /^=== STDERR ===$/ { in_stdout = 0 }
    in_stdout { print }
  ' "$input" >"$output"
}

"$ORIGINAL_CRYSTAL" build "$SRC" -o "$ORIGINAL_BIN"
"$ROOT_DIR/scripts/run_safe.sh" "$ORIGINAL_BIN" "$TIMEOUT_SECS" "$MAX_MEM_MB" >"$ORIGINAL_RUN_LOG" 2>&1
extract_run_safe_stdout "$ORIGINAL_RUN_LOG" "$ORIGINAL_STDOUT"

if ! "$COMPILER" "$SRC" -o "$STAGE_BIN" >"$STAGE_COMPILE_LOG" 2>&1; then
  echo "original-vs-stage semantic oracle: stage compiler failed" >&2
  tail -n 40 "$STAGE_COMPILE_LOG" >&2
  if [[ "$EXPECT_MISMATCH" == "1" ]]; then
    echo "MEASURED_RED: expected original-vs-stage mismatch via stage compile failure"
    exit 0
  fi
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$STAGE_BIN" "$TIMEOUT_SECS" "$MAX_MEM_MB" >"$STAGE_RUN_LOG" 2>&1
extract_run_safe_stdout "$STAGE_RUN_LOG" "$STAGE_STDOUT"

if diff -u "$ORIGINAL_STDOUT" "$STAGE_STDOUT" >"$WORKDIR/stdout.diff"; then
  if [[ "$EXPECT_MISMATCH" == "1" ]]; then
    echo "expected original-vs-stage semantic mismatch, but outputs matched" >&2
    cat "$ORIGINAL_STDOUT" >&2
    exit 1
  fi
  echo "PASS: original-vs-stage semantic oracle"
  exit 0
fi

echo "original-vs-stage semantic oracle mismatch" >&2
cat "$WORKDIR/stdout.diff" >&2

if [[ "$EXPECT_MISMATCH" == "1" ]]; then
  echo "MEASURED_RED: original-vs-stage semantic mismatch reproduced"
  exit 0
fi

exit 1
