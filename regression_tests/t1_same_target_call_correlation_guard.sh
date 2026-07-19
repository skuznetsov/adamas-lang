#!/usr/bin/env bash
# T1 downstream falsifier: compile a reducer with two distinct source calls to
# one non-inline Foo#bar(Int32), then inspect the bounded materialization log.
#
# The only accepted future producer is this exact, versioned row (field order and
# value domains are part of the probe contract):
#   [T1_RESOLUTION_TERMINAL] schema=t1_resolution_terminal_v1 \
#     resolution_id=<u64> callsite_id=<token> \
#     selected_def_arena_id=<u64> selected_def_expr_index=<i32> \
#     method_instance_id=<token> terminal=<materialized|cache_hit|inline|failed>
# Any tagged row is review-required until its producer is intentionally landed.
# A missing row is MEASURED_RED for this supplied compiler/configuration path;
# it is not a global proof that identity is absent or that continuity fails.
# Default MEASURED_RED exits 1; T1_SAME_TARGET_ALLOW_MEASURED_RED=1 accepts it
# with exit 0. The schema is generic; reducer target text is only a filter for
# observed structural MAT rows, never part of the future identity key.
# Operational errors exit 2.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER_ARGUMENT="${1:-$ROOT_DIR/bin/adamas}"
TIMEOUT_SEC="${T1_SAME_TARGET_TIMEOUT_SEC:-60}"
MEM_MB="${T1_SAME_TARGET_MEM_MB:-2048}"
MAX_LOG_BYTES="${T1_SAME_TARGET_MAX_LOG_BYTES:-262144}"
ALLOW_MEASURED_RED="${T1_SAME_TARGET_ALLOW_MEASURED_RED:-0}"
KEEP_TMP="${KEEP_TMP:-0}"

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [compiler]" >&2
  echo "env: T1_SAME_TARGET_ALLOW_MEASURED_RED=1 accepts MEASURED_RED (rc=0); schema appearance remains review-required (rc=1)" >&2
  exit 2
fi

if [[ ! "$MAX_LOG_BYTES" =~ ^[1-9][0-9]*$ ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "T1_SAME_TARGET_MAX_LOG_BYTES must be a positive decimal integer: $MAX_LOG_BYTES" >&2
  exit 2
fi
if [[ "$ALLOW_MEASURED_RED" != "0" && "$ALLOW_MEASURED_RED" != "1" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "T1_SAME_TARGET_ALLOW_MEASURED_RED must be 0 or 1: $ALLOW_MEASURED_RED" >&2
  exit 2
fi
if [[ ! "$TIMEOUT_SEC" =~ ^[1-9][0-9]*$ || ! "$MEM_MB" =~ ^[1-9][0-9]*$ ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "T1_SAME_TARGET_TIMEOUT_SEC and T1_SAME_TARGET_MEM_MB must be positive decimal integers" >&2
  exit 2
fi

if [[ "$COMPILER_ARGUMENT" == /* ]]; then
  COMPILER="$COMPILER_ARGUMENT"
elif [[ "$COMPILER_ARGUMENT" == */* ]]; then
  COMPILER="$(cd "$(dirname "$COMPILER_ARGUMENT")" 2>/dev/null && pwd)/$(basename "$COMPILER_ARGUMENT")" || COMPILER=""
else
  COMPILER="$(command -v "$COMPILER_ARGUMENT" 2>/dev/null || true)"
fi

if [[ ! -x "$COMPILER" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "missing executable compiler: argument=$COMPILER_ARGUMENT resolved=$COMPILER" >&2
  exit 2
fi

SRC="$ROOT_DIR/regression_tests/t1_same_target_calls.cr"
if [[ ! -s "$SRC" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "missing reducer: $SRC" >&2
  exit 2
fi

# Pin the source shape before invoking the compiler. This is the minimum
# non-vacuity condition: exactly one non-inline definition and two source call
# expressions selecting the same receiver/method spelling.
def_count="$(grep -Ec '^[[:space:]]*def[[:space:]]+bar\(value[[:space:]]*:[[:space:]]*Int32\)[[:space:]]*:[[:space:]]*Int32[[:space:]]*$' "$SRC" || true)"
call_one_count="$(grep -Ec '^[[:space:]]*first[[:space:]]*=[[:space:]]*foo\.bar\(1\)[[:space:]]*$' "$SRC" || true)"
call_two_count="$(grep -Ec '^[[:space:]]*second[[:space:]]*=[[:space:]]*foo\.bar\(2\)[[:space:]]*$' "$SRC" || true)"
echo "T1_SOURCE_DEF_FOO_BAR_INT32=$def_count"
echo "T1_SOURCE_CALL_ONE=$call_one_count"
echo "T1_SOURCE_CALL_TWO=$call_two_count"
if [[ "$def_count" -ne 1 || "$call_one_count" -ne 1 || "$call_two_count" -ne 1 ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "reducer shape changed; expected one Foo#bar(Int32) definition and two distinct calls" >&2
  exit 2
fi

LOG_CAP_BYTES=$((MAX_LOG_BYTES + 1))
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/t1_same_target_calls.XXXXXX")"
OUT="$TMP_DIR/t1_same_target_calls"
COMPILE_LOG="$TMP_DIR/compiler.log"
RUN_LOG="$TMP_DIR/reducer.log"

cleanup() {
  if [[ "$KEEP_TMP" == "1" ]]; then
    echo "T1_TMP_DIR=$TMP_DIR" >&2
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

# Store at most MAX_LOG_BYTES; the extra byte distinguishes a real overflow
# from a complete log. Both compiler and reducer are launched through run_safe.
set +e
ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
  "$SRC" --no-prelude -o "$OUT" 2>&1 | head -c "$LOG_CAP_BYTES" >"$COMPILE_LOG"
compile_pipe_status=("${PIPESTATUS[@]}")
set -e
compile_rc="${compile_pipe_status[0]:-2}"
compile_head_rc="${compile_pipe_status[1]:-2}"
compile_log_bytes="$(wc -c <"$COMPILE_LOG" | tr -d '[:space:]')"
echo "T1_COMPILER_RC=$compile_rc"
echo "T1_COMPILER_HEAD_RC=$compile_head_rc"
echo "T1_COMPILER_LOG_BYTES=$compile_log_bytes"
if [[ "$compile_head_rc" -ne 0 || "$compile_log_bytes" -gt "$MAX_LOG_BYTES" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "compiler log exceeded hard bound: bytes=$compile_log_bytes limit=$MAX_LOG_BYTES head_rc=$compile_head_rc" >&2
  sed -n '1,80p' "$COMPILE_LOG" >&2 || true
  exit 2
fi
if [[ "$compile_rc" -ne 0 || ! -x "$OUT" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "compiler failed or did not produce reducer binary: rc=$compile_rc output=$OUT" >&2
  sed -n '1,100p' "$COMPILE_LOG" >&2 || true
  exit 2
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 2>&1 | head -c "$LOG_CAP_BYTES" >"$RUN_LOG"
run_pipe_status=("${PIPESTATUS[@]}")
set -e
run_rc="${run_pipe_status[0]:-2}"
run_head_rc="${run_pipe_status[1]:-2}"
run_log_bytes="$(wc -c <"$RUN_LOG" | tr -d '[:space:]')"
echo "T1_REDUCER_RC=$run_rc"
echo "T1_REDUCER_HEAD_RC=$run_head_rc"
echo "T1_REDUCER_LOG_BYTES=$run_log_bytes"
if [[ "$run_head_rc" -ne 0 || "$run_log_bytes" -gt "$MAX_LOG_BYTES" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "reducer log exceeded hard bound: bytes=$run_log_bytes limit=$MAX_LOG_BYTES head_rc=$run_head_rc" >&2
  sed -n '1,80p' "$RUN_LOG" >&2 || true
  exit 2
fi
if [[ "$run_rc" -ne 0 ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "reducer runtime failed: rc=$run_rc" >&2
  sed -n '1,80p' "$RUN_LOG" >&2 || true
  exit 2
fi
echo "T1_RUNTIME_SOURCE_SHAPE=passed"

# Count observations without imposing a brittle expected MAT_TX cardinality.
# A cache hit may produce no target MAT_TX/MAT_DONE row; multiple structural
# rows may reuse one tx. Both are evidence for the diagnostic red, not errors.
read -r mat_tx_rows mat_tx_unique mat_done_rows mat_emit_rows mat_emit_none_tx tagged_terminal_rows exact_terminal_rows <<EOF
$(awk '
  function field(name,    i, p) {
    for (i = 1; i <= NF; i++) {
      p = index($i, "=")
      if (p > 0 && substr($i, 1, p - 1) == name) return substr($i, p + 1)
    }
    return ""
  }
  function has_target(    v) {
    v = field("requested"); if (v == "Foo#bar$Int32") return 1
    v = field("target"); if (v == "Foo#bar$Int32") return 1
    v = field("materialized"); if (v == "Foo#bar$Int32") return 1
    v = field("body_symbol"); if (v == "Foo#bar$Int32") return 1
    v = field("call_symbol_hint"); if (v == "Foo#bar$Int32") return 1
    v = field("emitted"); if (v == "Foo#bar$Int32") return 1
    return 0
  }
  function exact_terminal(line,    f, n, id, callsite, arena, expr, method, term) {
    n = split(line, f, " ")
    if (n != 8 || f[1] != "[T1_RESOLUTION_TERMINAL]" ||
        f[2] != "schema=t1_resolution_terminal_v1" ||
        f[3] !~ /^resolution_id=[0-9]+$/ ||
        f[4] !~ /^callsite_id=[^ ]+$/ ||
        f[5] !~ /^selected_def_arena_id=[0-9]+$/ ||
        f[6] !~ /^selected_def_expr_index=-?[0-9]+$/ ||
        f[7] !~ /^method_instance_id=[^ ]+$/ ||
        f[8] !~ /^terminal=(materialized|cache_hit|inline|failed)$/) return 0
    sub(/^resolution_id=/, "", f[3]); id = f[3]
    sub(/^callsite_id=/, "", f[4]); callsite = f[4]
    sub(/^selected_def_arena_id=/, "", f[5]); arena = f[5]
    sub(/^selected_def_expr_index=/, "", f[6]); expr = f[6]
    sub(/^method_instance_id=/, "", f[7]); method = f[7]
    return id ~ /^[0-9]+$/ && id != "" && callsite != "" && arena ~ /^[0-9]+$/ && \
      expr ~ /^-?[0-9]+$/ && method != ""
  }
  /^\[MAT_TX\]/ {
    if (has_target()) {
      mat_tx_rows++
      tx = field("tx")
      if (tx != "" && tx != "none") tx_seen[tx] = 1
    }
  }
  /^\[MAT_DONE\]/ { if (has_target()) mat_done_rows++ }
  /^\[MAT_EMIT\]/ {
    if (has_target()) {
      mat_emit_rows++
      if (field("tx") == "" || field("tx") == "none") mat_emit_none_tx++
    }
  }
  /^\[T1_RESOLUTION_TERMINAL\]/ {
    tagged_terminal_rows++
    if (exact_terminal($0)) exact_terminal_rows++
  }
  END {
    for (tx in tx_seen) mat_tx_unique++
    print mat_tx_rows + 0, mat_tx_unique + 0, mat_done_rows + 0, \
      mat_emit_rows + 0, mat_emit_none_tx + 0, tagged_terminal_rows + 0, \
      exact_terminal_rows + 0
  }
' "$COMPILE_LOG")
EOF

echo "T1_TARGET_MAT_TX_ROWS=$mat_tx_rows"
echo "T1_TARGET_MAT_TX_UNIQUE=$mat_tx_unique"
echo "T1_TARGET_MAT_DONE_ROWS=$mat_done_rows"
echo "T1_TARGET_MAT_EMIT_ROWS=$mat_emit_rows"
echo "T1_TARGET_MAT_EMIT_NONE_TX_ROWS=$mat_emit_none_tx"
echo "T1_TAGGED_TERMINAL_ROWS=$tagged_terminal_rows"
echo "T1_EXACT_TERMINAL_ROWS=$exact_terminal_rows"

if [[ "$tagged_terminal_rows" -gt 0 ]]; then
  echo "T1_STATUS=UNEXPECTED_SCHEMA_APPEARED" >&2
  echo "review required: T1_RESOLUTION_TERMINAL producer appeared before this guard was upgraded" >&2
  awk '/^\[T1_RESOLUTION_TERMINAL\]/ { print }' "$COMPILE_LOG" | head -20 >&2 || true
  exit 1
fi

if [[ "$mat_tx_rows" -eq 0 && "$mat_done_rows" -eq 0 && "$mat_emit_rows" -eq 0 ]]; then
  reason="t1_resolution_terminal_v1_absent; no Foo#bar structural MAT row observed (cache-hit, ledger gating, or path visibility may explain this)"
else
  reason="t1_resolution_terminal_v1_absent; structural MAT rows are symbol-scoped and not per-call ResolutionId terminals (cache-hit may omit MAT_TX/MAT_DONE; observed tx cardinality is diagnostic only)"
fi
echo "T1_STATUS=MEASURED_RED"
echo "T1_RED_REASON=$reason"
echo "T1_SCOPE=supplied_compiler_and_configuration_path_only_not_global_absence_or_continuity"
if [[ "$ALLOW_MEASURED_RED" == "1" ]]; then
  echo "T1_EXPECTED_EXIT=0"
  exit 0
fi
echo "T1_EXPECTED_EXIT=1"
exit 1
