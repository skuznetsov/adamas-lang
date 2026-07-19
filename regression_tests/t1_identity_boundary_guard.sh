#!/usr/bin/env bash
# T1 falsifier: measure availability of one exact, versioned producer record
# at the supplied compiler/configuration's resolution/materialization path.
# This guard is diagnostic: a current MEASURED_RED says only that the tagged
# schema is not emitted here; it does not prove identity is absent elsewhere or
# that continuity holds/fails. By default MEASURED_RED exits 1; set
# T1_ALLOW_MEASURED_RED=1 to accept that expected diagnostic exit 0. Any exact
# tagged record is UNEXPECTED_SCHEMA_APPEARED and requires review.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER_ARGUMENT="${1:-$ROOT_DIR/bin/adamas}"
TIMEOUT_SEC="${T1_TIMEOUT_SEC:-60}"
MEM_MB="${T1_MEM_MB:-2048}"
MAX_LOG_BYTES="${T1_MAX_LOG_BYTES:-262144}"
KEEP_TMP="${KEEP_TMP:-0}"
EXPECTED_COMPILER_SHA256="${T1_EXPECT_COMPILER_SHA256:-}"
ALLOW_MEASURED_RED="${T1_ALLOW_MEASURED_RED:-0}"

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [compiler]" >&2
  echo "env: T1_ALLOW_MEASURED_RED=1 accepts expected MEASURED_RED (rc=0); default MEASURED_RED is rc=1; schema review is rc=1; errors are rc=2" >&2
  exit 2
fi

if [[ ! "$MAX_LOG_BYTES" =~ ^[1-9][0-9]*$ ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "T1_MAX_LOG_BYTES must be a positive decimal integer: $MAX_LOG_BYTES" >&2
  exit 2
fi
if [[ "$ALLOW_MEASURED_RED" != "0" && "$ALLOW_MEASURED_RED" != "1" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "T1_ALLOW_MEASURED_RED must be 0 or 1: $ALLOW_MEASURED_RED" >&2
  exit 2
fi
LOG_CAP_BYTES=$((MAX_LOG_BYTES + 1))

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

if command -v shasum >/dev/null 2>&1; then
  COMPILER_SHA256="$(shasum -a 256 "$COMPILER" | awk '{print $1}')"
else
  COMPILER_SHA256="$(sha256sum "$COMPILER" | awk '{print $1}')"
fi
echo "T1_COMPILER_ARGUMENT=$COMPILER_ARGUMENT"
echo "T1_COMPILER_ABSOLUTE=$COMPILER"
echo "T1_COMPILER_SHA256=$COMPILER_SHA256"
echo "T1_ALLOW_MEASURED_RED=$ALLOW_MEASURED_RED"
if [[ -n "$EXPECTED_COMPILER_SHA256" && "$EXPECTED_COMPILER_SHA256" != "$COMPILER_SHA256" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "compiler sha256 mismatch: expected=$EXPECTED_COMPILER_SHA256 actual=$COMPILER_SHA256" >&2
  exit 2
fi

SRC="$ROOT_DIR/regression_tests/t1_same_spelling_shapes.cr"
if [[ ! -s "$SRC" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "missing reducer: $SRC" >&2
  exit 2
fi

# Pin the reducer's intended negative shapes before compiling it. This keeps a
# future fixture edit from turning a missing block/named row into a vacuous
# red result.
source_route_calls="$(grep -Ec '^[[:space:]]*r[1-5][[:space:]]*=[[:space:]].*\.route\(' "$SRC" || true)"
source_def_routes="$(grep -Ec '^[[:space:]]*def[[:space:]]+route\(' "$SRC" || true)"
source_block_calls="$(grep -Ec 'route\(2\)[[:space:]]*\{' "$SRC" || true)"
source_named_calls="$(grep -Ec 'route\(level:' "$SRC" || true)"
echo "T1_SOURCE_ROUTE_CALLS=$source_route_calls"
echo "T1_SOURCE_DEF_ROUTE_DECLS=$source_def_routes"
echo "T1_SOURCE_BLOCK_CALLS=$source_block_calls"
echo "T1_SOURCE_NAMED_CALLS=$source_named_calls"
if [[ "$source_route_calls" -ne 5 || "$source_def_routes" -ne 5 || \
      "$source_block_calls" -ne 1 || "$source_named_calls" -ne 1 ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "reducer shape counts changed; expected route=5 defs=5 block=1 named=1" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/t1_identity_boundary.XXXXXX")"
LOG="$TMP_DIR/compiler.log"
RUN_LOG="$TMP_DIR/run.log"
OUT="$TMP_DIR/t1_same_spelling_shapes"

cleanup() {
  if [[ "$KEEP_TMP" == "1" ]]; then
    echo "T1_TMP_DIR=$TMP_DIR" >&2
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

# The compiler and produced reducer are both launched through run_safe.sh. The
# head stage is deliberately one byte over the accepted cap: a stored log of
# MAX_LOG_BYTES+1 is an overflow error, while no stored artifact can grow
# beyond that bound.
set +e
ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
  "$SRC" --no-prelude -o "$OUT" 2>&1 | head -c "$LOG_CAP_BYTES" >"$LOG"
compile_pipe_status=("${PIPESTATUS[@]}")
set -e
compile_rc="${compile_pipe_status[0]:-2}"
compile_head_rc="${compile_pipe_status[1]:-2}"

log_bytes="$(wc -c <"$LOG" | tr -d '[:space:]')"
echo "T1_COMPILER_RC=$compile_rc"
echo "T1_COMPILER_HEAD_RC=$compile_head_rc"
echo "T1_LOG_BYTES=$log_bytes"
if [[ "$compile_head_rc" -ne 0 || "$log_bytes" -gt "$MAX_LOG_BYTES" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "compiler log exceeded hard bound or cap stage failed: bytes=$log_bytes limit=$MAX_LOG_BYTES head_rc=$compile_head_rc" >&2
  sed -n '1,80p' "$LOG" >&2 || true
  exit 2
fi

if [[ "$compile_rc" -ne 0 || ! -x "$OUT" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "compiler failed or did not produce reducer binary: rc=$compile_rc" >&2
  sed -n '1,100p' "$LOG" >&2 || true
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
echo "T1_RUN_LOG_BYTES=$run_log_bytes"
if [[ "$run_head_rc" -ne 0 || "$run_log_bytes" -gt "$MAX_LOG_BYTES" ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "reducer log exceeded hard bound or cap stage failed: bytes=$run_log_bytes limit=$MAX_LOG_BYTES head_rc=$run_head_rc" >&2
  sed -n '1,80p' "$RUN_LOG" >&2 || true
  exit 2
fi
if [[ "$run_rc" -ne 0 ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "reducer runtime failed: rc=$run_rc" >&2
  sed -n '1,80p' "$RUN_LOG" >&2 || true
  exit 2
fi
echo "T1_RUNTIME_TUPLE_CHECK=passed"

# Count the current legacy route rows and recognize only this exact future
# record. Field order and value domains are part of the v1 schema; permissive
# aliases are deliberately not accepted.
read -r mat_rows tagged_rows exact_schema_rows malformed_schema_rows \
  legacy_r1_rows legacy_r2_rows legacy_r3_rows legacy_r4_rows legacy_r5_rows <<EOF
$(awk '
  function is_u32(value) {
    return value ~ /^[0-9]+$/ && (value + 0) <= 4294967295
  }
  function is_u64(value, normalized, limit) {
    if (value !~ /^[0-9]+$/) return 0
    normalized = value
    sub(/^0+/, "", normalized)
    if (normalized == "") normalized = "0"
    limit = "18446744073709551615"
    if (length(normalized) < length(limit)) return 1
    if (length(normalized) > length(limit)) return 0
    # Prefix both operands so awk performs lexical, not floating-point,
    # comparison after leading-zero normalization.
    return ("u64:" normalized) <= ("u64:" limit)
  }
  function is_i32(value) {
    return value ~ /^-?[0-9]+$/ && (value + 0) >= -2147483648 && \
      (value + 0) <= 2147483647
  }
  function is_u32_list(value, parts, count, i) {
    if (value == "none") return 1
    count = split(value, parts, ",")
    for (i = 1; i <= count; i++) {
      if (!is_u32(parts[i])) return 0
    }
    return 1
  }
  function is_named_list(value, parts, count, i, pair, pair_count) {
    if (value == "none") return 1
    count = split(value, parts, ",")
    for (i = 1; i <= count; i++) {
      pair_count = split(parts[i], pair, ":")
      if (pair_count != 2 || !is_u32(pair[1]) || !is_u32(pair[2])) {
        return 0
      }
    }
    return 1
  }
  function is_exact_t1_schema(line, fields, count) {
    count = split(line, fields, " ")
    if (count != 11 || fields[1] != "[T1_IDENTITY_JOIN]" || \
        fields[2] != "schema=t1_identity_join_v1" || \
        fields[3] !~ /^case_id=r[1-5]$/ || \
        fields[4] !~ /^resolution_id=[0-9]+$/ || \
        fields[5] !~ /^def_arena_id=[0-9]+$/ || \
        fields[6] !~ /^def_expr_index=-?[0-9]+$/ || \
        fields[7] !~ /^receiver_semantic_type_id=(none|[0-9]+)$/ || \
        fields[8] !~ /^arg_semantic_type_ids=(none|[0-9]+(,[0-9]+)*)$/ || \
        fields[9] !~ /^block_semantic_type_id=(none|[0-9]+)$/ || \
        fields[10] !~ /^named_semantic_args=(none|[0-9]+:[0-9]+(,[0-9]+:[0-9]+)*)$/ || \
        fields[11] != "producer_phase=post_resolution_pre_hir_coercion") {
      return 0
    }
    sub(/^resolution_id=/, "", fields[4])
    sub(/^def_arena_id=/, "", fields[5])
    sub(/^def_expr_index=/, "", fields[6])
    sub(/^receiver_semantic_type_id=/, "", fields[7])
    sub(/^arg_semantic_type_ids=/, "", fields[8])
    sub(/^block_semantic_type_id=/, "", fields[9])
    sub(/^named_semantic_args=/, "", fields[10])
    return is_u64(fields[4]) && is_u64(fields[5]) && is_i32(fields[6]) && \
      (fields[7] == "none" || is_u32(fields[7])) && \
      is_u32_list(fields[8]) && (fields[9] == "none" || is_u32(fields[9])) && \
      is_named_list(fields[10])
  }
  /^\[(MAT_ID|MAT_TX|MAT_DONE|MAT_EMIT)\]/ {
    mat_rows++
    if (index($0, "T1Left#route$Int32") > 0) legacy_r1_rows++
    if (index($0, "T1Left#route$String") > 0) legacy_r2_rows++
    if (index($0, "T1Right#route$Int32") > 0) legacy_r3_rows++
    if (index($0, "T1Block#route$Int32") > 0) legacy_r4_rows++
    if (index($0, "T1Named#route$Int32") > 0) legacy_r5_rows++
  }
  /^\[T1_IDENTITY_JOIN\]/ {
    tagged_rows++
    if (is_exact_t1_schema($0)) exact_schema_rows++
    else malformed_schema_rows++
  }
  END {
    print mat_rows + 0, tagged_rows + 0, exact_schema_rows + 0, \
      malformed_schema_rows + 0, legacy_r1_rows + 0, legacy_r2_rows + 0, \
      legacy_r3_rows + 0, legacy_r4_rows + 0, legacy_r5_rows + 0
  }
' "$LOG")
EOF

echo "T1_MAT_ROWS=$mat_rows"
echo "T1_TAGGED_SCHEMA_ROWS=$tagged_rows"
echo "T1_EXACT_SCHEMA_ROWS=$exact_schema_rows"
echo "T1_MALFORMED_SCHEMA_ROWS=$malformed_schema_rows"
echo "T1_LEGACY_R1_ROWS=$legacy_r1_rows"
echo "T1_LEGACY_R2_ROWS=$legacy_r2_rows"
echo "T1_LEGACY_R3_ROWS=$legacy_r3_rows"
echo "T1_LEGACY_R4_ROWS=$legacy_r4_rows"
echo "T1_LEGACY_R5_ROWS=$legacy_r5_rows"
echo "T1_DECLARED_SHAPE_CALLS=5"
echo "T1_SOURCE_BLOCK_CALLS=$source_block_calls"
echo "T1_SOURCE_NAMED_CALLS=$source_named_calls"
echo "T1_R4_CLASSIFICATION=runtime_executed_inline_block_route"
echo "T1_R4_EVIDENCE=source_block_call_and_runtime_tuple_passed;legacy_mat_rows:${legacy_r4_rows}"
echo "T1_FULL_ACCEPTANCE=pending_exactly_5_tagged_rows_and_downstream_correlation"

if [[ "$mat_rows" -lt 1 || "$legacy_r1_rows" -lt 1 || \
      "$legacy_r2_rows" -lt 1 || "$legacy_r3_rows" -lt 1 || \
      "$legacy_r5_rows" -lt 1 ]]; then
  echo "T1_STATUS=ERROR" >&2
  echo "expected T1-specific legacy route rows were not observed" >&2
  sed -n '1,100p' "$LOG" >&2 || true
  exit 2
fi

if [[ "$tagged_rows" -gt 0 ]]; then
  echo "T1_STATUS=UNEXPECTED_SCHEMA_APPEARED" >&2
  echo "review required: exact or malformed T1 identity schema record appeared" >&2
  exit 1
fi

echo "T1_STATUS=MEASURED_RED"
echo "T1_RED_REASON=t1_identity_join_v1_schema_unavailable_for_supplied_compiler_config_path"
echo "T1_SCOPE=supplied_compiler_and_configuration_path_availability_only_not_global_absence_or_continuity"
if [[ "$ALLOW_MEASURED_RED" == "1" ]]; then
  echo "T1_EXPECTED_EXIT=0"
  exit 0
fi
echo "T1_EXPECTED_EXIT=1"
exit 1
