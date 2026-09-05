#!/usr/bin/env bash
set -euo pipefail

# A generated stage2 compiler must retain the MIR definition for an
# interpolation value when LLVMIRGenerator#value_ref resolves it.  The
# backend's find_def_inst scan is on this path; a missing definition becomes
# `ptr null` in the generated LLVM and silently drops the line.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE2="${1:?usage: $0 <generated-stage2-compiler>}"
TMP_DIR="$(mktemp -d /tmp/p2_generated_stage2_find_def_inst_XXXXXX)"
SOURCE="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_generated_stage2_find_def_inst] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

if [[ ! -x "$STAGE2" ]]; then
  echo "p2_generated_stage2_find_def_inst_failed: compiler not found: $STAGE2" >&2
  exit 2
fi

cat >"$SOURCE" <<'CR'
name = "world"
n = 42
puts "hello #{name}"
puts "n=#{n}"
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$STAGE2" 60 1024 \
  "$SOURCE" --no-prelude -o "$OUT" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 || ! -x "$OUT" ]]; then
  echo "p2_generated_stage2_find_def_inst_failed: stage2 compile exited $compile_status" >&2
  tail -120 "$COMPILE_LOG" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1

actual_stdout="$(awk '/^=== STDOUT ===$/{capture=1; next} /^=== STDERR ===$/{capture=0} capture {print}' "$RUN_LOG" | tr -d '\r')"
if [[ "$actual_stdout" != $'hello world\nn=42' ]]; then
  echo "p2_generated_stage2_find_def_inst_failed: interpolation output was lost" >&2
  printf 'expected stdout:\nhello world\nn=42\nactual stdout:\n%s\nraw run log:\n' "$actual_stdout" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_generated_stage2_find_def_inst_no_prelude_ok"
