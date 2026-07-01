#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_transaction_spine_classifier.sh [source.cr]

Build/use a fresh generated s2 compiler, compile a full-prelude source with the
materialization transaction ledger enabled, and classify whether the active
generated-stage frontier reaches the CallMaterializationTransaction spine.

Environment:
  STAGE1_COMPILER       Use an existing stage1 compiler instead of building one.
  GENERATED_S2          Use an existing generated s2 compiler instead of building one.
  KEEP_TMP=1            Keep the temporary directory and print its path.
  REQUIRE_REACHED=1     Exit nonzero unless classification=reached_tx_and_emit.
  STAGE2_BUILD_TIMEOUT  run_safe timeout for building generated s2 (default: 600).
  STAGE2_BUILD_MEM_MB   run_safe RSS cap for building generated s2 (default: 4096).
  SMOKE_TIMEOUT         run_safe timeout for full-prelude classifier compile (default: 180).
  SMOKE_MEM_MB          run_safe RSS cap for full-prelude classifier compile (default: 4096).
  SAMPLE_ROWS           Number of sample [MAT_TX]/[MAT_EMIT] rows (default: 3).
  TAIL_LINES            Failure/frontier tail lines to print (default: 40).

Classifications:
  reached_tx_and_emit   [MAT_TX] rows and transaction-bound [MAT_EMIT] rows were both reached.
  tx_only_no_emit       [MAT_TX] rows were reached, but no transaction-bound [MAT_EMIT] rows.
  no_tx_rows            no [MAT_TX] rows before the compile frontier.
  s2_build_fails        generated s2 could not be built or was not executable.
  stage1_build_fails    host Crystal could not build the stage1 compiler.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-tx-spine.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SOURCE="${1:-$TMP_DIR/full_prelude_puts42.cr}"
if [[ $# -eq 0 ]]; then
  cat >"$SOURCE" <<'CR'
puts 42
CR
fi

STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-600}"
STAGE2_BUILD_MEM_MB="${STAGE2_BUILD_MEM_MB:-4096}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-180}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"
SAMPLE_ROWS="${SAMPLE_ROWS:-3}"
TAIL_LINES="${TAIL_LINES:-40}"

STAGE1="${STAGE1_COMPILER:-$TMP_DIR/adamas_stage1}"
S2="${GENERATED_S2:-$TMP_DIR/adamas_s2}"
STAGE1_LOG="$TMP_DIR/stage1_build.log"
S2_BUILD_LOG="$TMP_DIR/s2_build.log"
CLASSIFY_LOG="$TMP_DIR/classifier_compile.log"
OUT_BIN="$TMP_DIR/full_prelude_out"

print_header() {
  echo "# Generated Stage Transaction Spine Classifier"
  echo "repo=$ROOT_DIR"
  echo "source=$SOURCE"
  echo "stage1=$STAGE1"
  echo "generated_s2=$S2"
  echo "stage2_build_timeout=$STAGE2_BUILD_TIMEOUT"
  echo "stage2_build_mem_mb=$STAGE2_BUILD_MEM_MB"
  echo "smoke_timeout=$SMOKE_TIMEOUT"
  echo "smoke_mem_mb=$SMOKE_MEM_MB"
  echo "sample_rows=$SAMPLE_ROWS"
  echo "tail_lines=$TAIL_LINES"
  echo "require_reached=${REQUIRE_REACHED:-0}"
}

finish_classification() {
  local classification="$1"
  local rc="${2:-0}"

  echo "classification=$classification"
  echo "stage1_build_log=$STAGE1_LOG"
  echo "s2_build_log=$S2_BUILD_LOG"
  echo "classifier_log=$CLASSIFY_LOG"

  if [[ "${REQUIRE_REACHED:-0}" == "1" && "$classification" != "reached_tx_and_emit" ]]; then
    exit "${rc:-9}"
  fi
  exit 0
}

print_header

if [[ -z "${STAGE1_COMPILER:-}" ]]; then
  set +e
  "$ROOT_DIR/scripts/build_stage1_original_cached.sh" debug "$STAGE1" --error-trace >"$STAGE1_LOG" 2>&1
  stage1_rc=$?
  set -e
  echo "stage1_build_rc=$stage1_rc"
  if [[ $stage1_rc -ne 0 || ! -x "$STAGE1" ]]; then
    echo "stage1_build_tail:"
    tail -80 "$STAGE1_LOG" || true
    finish_classification "stage1_build_fails" 8
  fi
else
  echo "stage1_build_rc=skipped"
  if [[ ! -x "$STAGE1" ]]; then
    echo "provided_stage1_not_executable=$STAGE1"
    finish_classification "stage1_build_fails" 8
  fi
fi

if [[ -z "${GENERATED_S2:-}" ]]; then
  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$STAGE1" "$STAGE2_BUILD_TIMEOUT" "$STAGE2_BUILD_MEM_MB" \
    "$ROOT_DIR/src/adamas.cr" -o "$S2" >"$S2_BUILD_LOG" 2>&1
  s2_build_rc=$?
  set -e
  echo "s2_build_rc=$s2_build_rc"
  if [[ $s2_build_rc -ne 0 || ! -x "$S2" ]]; then
    echo "s2_build_tail:"
    tail -100 "$S2_BUILD_LOG" || true
    finish_classification "s2_build_fails" 9
  fi
else
  echo "s2_build_rc=skipped"
  if [[ ! -x "$S2" ]]; then
    echo "provided_generated_s2_not_executable=$S2"
    finish_classification "s2_build_fails" 9
  fi
fi

set +e
ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$S2" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
    "$SOURCE" -o "$OUT_BIN" >"$CLASSIFY_LOG" 2>&1
compile_rc=$?
set -e

tx_rows="$(grep -c '^\[MAT_TX\]' "$CLASSIFY_LOG" || true)"
emit_rows="$(grep -c '^\[MAT_EMIT\]' "$CLASSIFY_LOG" || true)"
joined_emit_rows="$(
  awk '
    /^\[MAT_EMIT\]/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^tx=/) {
          tx = substr($i, 4)
          if (tx != "" && tx != "none") {
            count++
          }
        }
      }
    }
    END { print count + 0 }
  ' "$CLASSIFY_LOG"
)"
mat_id_rows="$(grep -c '^\[MAT_ID\]' "$CLASSIFY_LOG" || true)"
stub_rows="$(grep -c 'STUB CALLED' "$CLASSIFY_LOG" || true)"

echo "compiler_rc=$compile_rc"
echo "mat_id_rows=$mat_id_rows"
echo "mat_tx_rows=$tx_rows"
echo "mat_emit_rows=$emit_rows"
echo "transaction_bound_mat_emit_rows=$joined_emit_rows"
echo "stub_rows=$stub_rows"

if [[ "$tx_rows" -gt 0 && "$joined_emit_rows" -gt 0 ]]; then
  classification="reached_tx_and_emit"
elif [[ "$tx_rows" -gt 0 ]]; then
  classification="tx_only_no_emit"
else
  classification="no_tx_rows"
fi

echo "sample_mat_tx:"
grep '^\[MAT_TX\]' "$CLASSIFY_LOG" | head -"$SAMPLE_ROWS" || true
echo "sample_mat_emit:"
awk '
  /^\[MAT_EMIT\]/ {
    tx = ""
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^tx=/) tx = substr($i, 4)
    }
    if (tx != "" && tx != "none") print
  }
' "$CLASSIFY_LOG" | head -"$SAMPLE_ROWS" || true

if [[ "$classification" != "reached_tx_and_emit" || "$compile_rc" -ne 0 ]]; then
  echo "classifier_tail:"
  tail -"$TAIL_LINES" "$CLASSIFY_LOG" || true
fi

finish_classification "$classification" 9
