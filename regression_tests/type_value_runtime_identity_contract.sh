#!/usr/bin/env bash
# H6 contract guard: type-visible values should share one semantic identity
# across typeof, runtime .class, direct output, interpolation, and type-literal
# name/string queries.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-crystal}"
TIMEOUT_SECS="${TYPEVALUE_ORACLE_TIMEOUT:-5}"
MAX_MEM_MB="${TYPEVALUE_ORACLE_MAX_MEM:-512}"
EXPECT_MISMATCH="${ADAMAS_EXPECT_TYPEVALUE_MISMATCH:-0}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi
if ! command -v "$ORIGINAL_CRYSTAL" >/dev/null 2>&1; then
  echo "ERROR: original Crystal compiler not found: $ORIGINAL_CRYSTAL" >&2
  exit 2
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/type_value_runtime_identity.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

SRC="$WORKDIR/type_value.cr"
ORIGINAL_BIN="$WORKDIR/original_bin"
STAGE_BIN="$WORKDIR/stage_bin"
ORIGINAL_RUN_LOG="$WORKDIR/original.run.log"
STAGE_RUN_LOG="$WORKDIR/stage.run.log"
ORIGINAL_STDOUT="$WORKDIR/original.stdout"
STAGE_STDOUT="$WORKDIR/stage.stdout"
STAGE_COMPILE_LOG="$WORKDIR/stage.compile.log"

cat >"$SRC" <<'CRYSTAL'
puts "DIRECT_TYPEOF"
puts typeof(1)
puts "INTERP_TYPEOF=#{typeof(1)}"
puts "DIRECT_CLASS"
puts 1.class
puts "INTERP_CLASS=#{1.class}"
puts "DIRECT_NILABLE_CLASS"
puts (true ? 1 : nil).class
puts "INTERP_NILABLE_CLASS=#{(true ? 1 : nil).class}"
puts "TYPE_NAME=#{Int32.name}"
puts "TYPE_TO_S=#{Int32.to_s}"
puts "TYPE_INSPECT=#{Int32.inspect}"
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
  echo "type-value runtime identity oracle: stage compiler failed" >&2
  tail -n 40 "$STAGE_COMPILE_LOG" >&2
  if [[ "$EXPECT_MISMATCH" == "1" ]]; then
    echo "MEASURED_RED: expected TypeValue mismatch via stage compile failure"
    exit 0
  fi
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$STAGE_BIN" "$TIMEOUT_SECS" "$MAX_MEM_MB" >"$STAGE_RUN_LOG" 2>&1
stage_run_rc=$?
set -e
if [[ $stage_run_rc -ne 0 ]]; then
  echo "type-value runtime identity oracle: stage binary failed (rc=$stage_run_rc)" >&2
  tail -n 80 "$STAGE_RUN_LOG" >&2 || true
  if [[ "$EXPECT_MISMATCH" == "1" ]]; then
    echo "MEASURED_RED: expected TypeValue mismatch via stage runtime failure"
    exit 0
  fi
  exit 1
fi
extract_run_safe_stdout "$STAGE_RUN_LOG" "$STAGE_STDOUT"

if diff -u "$ORIGINAL_STDOUT" "$STAGE_STDOUT" >"$WORKDIR/stdout.diff"; then
  if [[ "$EXPECT_MISMATCH" == "1" ]]; then
    echo "expected TypeValue runtime identity mismatch, but outputs matched" >&2
    cat "$ORIGINAL_STDOUT" >&2
    exit 1
  fi
  echo "PASS: TypeValue runtime identity oracle"
  exit 0
fi

echo "TypeValue runtime identity oracle mismatch" >&2
cat "$WORKDIR/stdout.diff" >&2

if [[ "$EXPECT_MISMATCH" == "1" ]]; then
  echo "MEASURED_RED: TypeValue runtime identity mismatch reproduced"
  exit 0
fi

exit 1
