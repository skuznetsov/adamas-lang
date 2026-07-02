#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_execution_transaction_report.sh [source.cr]

Build/use the produced-stage LLVM-entry classifier, join its evidence with the
LLVMEmissionSession source-shape guard, and emit one GeneratedStageExecution
transaction row set for the produced-compiler invocation.

Environment:
  KEEP_TMP=1                  Keep transaction and nested classifier temp dirs.
  REQUIRE_CURRENT_FRONTIER=1  Require the current 0k-BN/B4 frontier.
  REQUIRE_CLEAN=1             Require final_classification=commit_clean.
  REQUIRE_JOINED=1            Require joined runtime evidence instead of
                              abort_unjoined_evidence.
  REQUIRE_ADMIT_BEHAVIOR=1    Require the report to select a behavior-admissible
                              root-sized transaction-owned edge.

Pass-through classifier environment:
  STAGE1_COMPILER, GENERATED_S2, STAGE1_MODE, STAGE2_BUILD_TIMEOUT,
  STAGE2_BUILD_MEM_MB, SMOKE_TIMEOUT, SMOKE_MEM_MB, TAIL_LINES.

Current expected state:
  The report should reach B4's measured-red generated-stage frontier, print one
  transaction_id, and classify admission as rejected_unjoined_evidence until
  runtime transaction rows exist. It is a guard/report, not a compiler behavior
  change and not green s2b/s3b evidence.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-execution-tx.XXXXXX")"
CLASSIFIER_OUT="$TMP_DIR/classifier.out"
SHAPE_OUT="$TMP_DIR/source_shape.out"
NESTED_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    if [[ -n "$NESTED_TMP" ]]; then
      echo "kept_classifier_tmp=$NESTED_TMP"
    fi
  else
    if [[ -n "$NESTED_TMP" && "$NESTED_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]]; then
      rm -rf "$NESTED_TMP"
    fi
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

value_of() {
  local key="$1"
  local file="$2"
  awk -F= -v k="$key" '
    $1 == k {
      print substr($0, index($0, "=") + 1)
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$file" 2>/dev/null || true
}

required_value() {
  local key="$1"
  local file="$2"
  local value
  value="$(value_of "$key" "$file")"
  if [[ -z "$value" ]]; then
    echo "missing:$key"
  else
    echo "$value"
  fi
}

sha1_text() {
  if command -v shasum >/dev/null 2>&1; then
    shasum | awk '{print $1}'
  else
    sha1sum | awk '{print $1}'
  fi
}

file_sha1() {
  local path="$1"
  if [[ -f "$path" ]]; then
    if command -v shasum >/dev/null 2>&1; then
      shasum "$path" | awk '{print $1}'
    else
      sha1sum "$path" | awk '{print $1}'
    fi
  else
    echo "unavailable"
  fi
}

set +e
KEEP_TMP=1 "$ROOT_DIR/scripts/generated_stage_llvm_entry_classifier.sh" "$@" >"$CLASSIFIER_OUT" 2>&1
classifier_rc=$?
set -e

NESTED_TMP="$(value_of "kept_tmp" "$CLASSIFIER_OUT")"

set +e
REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1 \
  "$ROOT_DIR/scripts/llvm_emission_session_source_shape_guard.sh" >"$SHAPE_OUT" 2>&1
shape_rc=$?
set -e

repo="$(required_value "repo" "$CLASSIFIER_OUT")"
source_path="$(required_value "source" "$CLASSIFIER_OUT")"
stage1_path="$(required_value "stage1" "$CLASSIFIER_OUT")"
generated_s2_path="$(required_value "generated_s2" "$CLASSIFIER_OUT")"
source_sha1="$(file_sha1 "$source_path")"
stage1_sha1="$(file_sha1 "$stage1_path")"
generated_s2_sha1="$(file_sha1 "$generated_s2_path")"
b4_classification="$(required_value "classification" "$CLASSIFIER_OUT")"
stage1_build_rc="$(required_value "stage1_build_rc" "$CLASSIFIER_OUT")"
s2_build_rc="$(required_value "s2_build_rc" "$CLASSIFIER_OUT")"
default_workers_rc="$(required_value "default_workers_rc" "$CLASSIFIER_OUT")"
workers1_rc="$(required_value "workers1_rc" "$CLASSIFIER_OUT")"
default_workers_after_lower_main="$(required_value "default_workers_after_lower_main" "$CLASSIFIER_OUT")"
workers1_after_lower_main="$(required_value "workers1_after_lower_main" "$CLASSIFIER_OUT")"
default_workers_parallel_rand="$(required_value "default_workers_parallel_rand" "$CLASSIFIER_OUT")"
default_workers_memory_kill="$(required_value "default_workers_memory_kill" "$CLASSIFIER_OUT")"
workers1_parallel_rand="$(required_value "workers1_parallel_rand" "$CLASSIFIER_OUT")"
workers1_exit139="$(required_value "workers1_exit139" "$CLASSIFIER_OUT")"
default_workers_binary_present="$(required_value "default_workers_binary_present" "$CLASSIFIER_OUT")"
workers1_binary_present="$(required_value "workers1_binary_present" "$CLASSIFIER_OUT")"

source_shape="$(required_value "source_shape" "$SHAPE_OUT")"
worker_shape="$(required_value "worker_shape" "$SHAPE_OUT")"
side_effect_contract_shape="$(required_value "side_effect_contract_shape" "$SHAPE_OUT")"
parallel_contract_writer_call_count="$(required_value "parallel_contract_writer_call_count" "$SHAPE_OUT")"
parallel_contract_merge_call_count="$(required_value "parallel_contract_merge_call_count" "$SHAPE_OUT")"
parallel_raw_side_effect_writer_tags="$(required_value "parallel_raw_side_effect_writer_tags" "$SHAPE_OUT")"
parallel_raw_side_effect_merge_tags="$(required_value "parallel_raw_side_effect_merge_tags" "$SHAPE_OUT")"

tx_seed="$repo|$source_path|$stage1_path|$generated_s2_path|$b4_classification|$source_shape|$worker_shape|$side_effect_contract_shape"
transaction_id="gsetx_$(printf '%s' "$tx_seed" | sha1_text | cut -c1-16)"

malformed=0
for value in \
  "$repo" "$source_path" "$stage1_path" "$generated_s2_path" "$b4_classification" \
  "$stage1_build_rc" "$s2_build_rc" "$default_workers_rc" "$workers1_rc" \
  "$source_shape" "$worker_shape" "$side_effect_contract_shape"; do
  if [[ "$value" == missing:* ]]; then
    malformed=1
  fi
done

if [[ $shape_rc -ne 0 || $malformed -eq 1 ]]; then
  final_classification="abort_malformed_transaction"
  admission_status="rejected_malformed_transaction"
  join_status="malformed"
elif [[ "$b4_classification" == "clean_both_modes" ]]; then
  final_classification="commit_clean"
  admission_status="candidate_clean_requires_joined_runtime_rows"
  join_status="phase_local_only"
elif [[ "$b4_classification" == "current_0k_bn_frontier" ]]; then
  final_classification="abort_unjoined_evidence"
  admission_status="rejected_unjoined_evidence"
  join_status="phase_local_only"
else
  final_classification="abort_unjoined_evidence"
  admission_status="rejected_unjoined_evidence"
  join_status="phase_local_only"
fi

if [[ "$join_status" == "phase_local_only" ]]; then
  unjoined_reason="missing_runtime_transaction_rows:hir_module_id,mir_module_id,llvm_emission_session_id,runtime_side_effect_row_counts,tail_semantic_vs_input_split,output_commit_record"
else
  unjoined_reason="none"
fi

echo "# Generated Stage Execution Transaction Report"
echo "repo=$ROOT_DIR"
echo "transaction_id=$transaction_id"
echo "transaction_count=1"
echo "classifier_rc=$classifier_rc"
echo "shape_guard_rc=$shape_rc"
echo "require_current_frontier=${REQUIRE_CURRENT_FRONTIER:-0}"
echo "require_clean=${REQUIRE_CLEAN:-0}"
echo "require_joined=${REQUIRE_JOINED:-0}"
echo "require_admit_behavior=${REQUIRE_ADMIT_BEHAVIOR:-0}"
echo "invocation.source=$source_path"
echo "invocation.source_sha1=$source_sha1"
echo "invocation.stage1=$stage1_path"
echo "invocation.stage1_sha1=$stage1_sha1"
echo "invocation.generated_s2=$generated_s2_path"
echo "invocation.generated_s2_sha1=$generated_s2_sha1"
echo "setup.source_shape=$source_shape"
echo "setup.worker_shape=$worker_shape"
echo "setup.side_effect_contract_shape=$side_effect_contract_shape"
echo "setup.runtime_session_id=unjoined"
echo "function_plan.source_status=$source_shape"
echo "function_plan.runtime_plan_rows=unjoined"
echo "worker_plan.default_rc=$default_workers_rc"
echo "worker_plan.workers1_rc=$workers1_rc"
echo "worker_plan.default_after_lower_main=$default_workers_after_lower_main"
echo "worker_plan.workers1_after_lower_main=$workers1_after_lower_main"
echo "worker_plan.default_parallel_rand=$default_workers_parallel_rand"
echo "worker_plan.workers1_parallel_rand=$workers1_parallel_rand"
echo "side_effect.contract_writer_calls=$parallel_contract_writer_call_count"
echo "side_effect.contract_merge_calls=$parallel_contract_merge_call_count"
echo "side_effect.raw_writer_tags=$parallel_raw_side_effect_writer_tags"
echo "side_effect.raw_merge_tags=$parallel_raw_side_effect_merge_tags"
echo "side_effect.runtime_row_counts=unjoined"
echo "tail.default_parallel_rand=$default_workers_parallel_rand"
echo "tail.workers1_exit139=$workers1_exit139"
echo "tail.semantic_vs_input_split=unjoined"
echo "output.default_binary_present=$default_workers_binary_present"
echo "output.workers1_binary_present=$workers1_binary_present"
echo "output.commit_record=unjoined"
echo "resource.default_memory_kill=$default_workers_memory_kill"
echo "resource.workers1_exit139=$workers1_exit139"
echo "resource.worker_mode_split=default_vs_workers1"
echo "b4.classification=$b4_classification"
echo "final_classification=$final_classification"
echo "join_status=$join_status"
echo "unjoined_reason=$unjoined_reason"
echo "admission_status=$admission_status"

exit_code=0
if [[ "${REQUIRE_CURRENT_FRONTIER:-0}" == "1" && "$b4_classification" != "current_0k_bn_frontier" ]]; then
  exit_code=9
fi
if [[ "${REQUIRE_CLEAN:-0}" == "1" && "$final_classification" != "commit_clean" ]]; then
  exit_code=9
fi
if [[ "${REQUIRE_JOINED:-0}" == "1" && "$join_status" != "joined" ]]; then
  exit_code=9
fi
if [[ "${REQUIRE_ADMIT_BEHAVIOR:-0}" == "1" && "$admission_status" != "admit_behavior_candidate" ]]; then
  exit_code=9
fi

exit "$exit_code"
