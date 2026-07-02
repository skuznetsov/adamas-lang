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
  REQUIRE_POST_CU_RESOURCE=1  Require the post-0k-CU joined resource frontier.
  REQUIRE_RESOURCE_PHASE_SPLIT=1
                              Require LLVM generate phase evidence for the
                              post-lower_main resource corridor.
  REQUIRE_FUNCTION_EMISSION_SPLIT=1
                              Require LLVM function-emission subphase evidence
                              for the current resource corridor.
  REQUIRE_WORKER_MODE_BOUNDARY=1
                              Require mode-local boundary classification for
                              the default and workers=1 resource corridors.
  REQUIRE_ADMIT_BEHAVIOR=1    Require the report to select a behavior-admissible
                              root-sized transaction-owned edge.

Pass-through classifier environment:
  STAGE1_COMPILER, GENERATED_S2, STAGE1_MODE, STAGE2_BUILD_TIMEOUT,
  STAGE2_BUILD_MEM_MB, SMOKE_TIMEOUT, SMOKE_MEM_MB, TAIL_LINES.

Current expected state:
  The report should reach B4's measured-red generated-stage frontier, print one
  transaction_id, join default-off runtime rows, and classify admission as
  rejected_no_root_sized_consumer until a later selector chooses exactly one
  transaction-owned behavior edge. It is a guard/report, not green s2b/s3b
  evidence.
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
RUNTIME_LEDGER="$TMP_DIR/runtime_ledger.tsv"
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

tx_seed="$ROOT_DIR|${1:-default-source}|$TMP_DIR|generated-stage-execution"
transaction_id="gsetx_$(printf '%s' "$tx_seed" | sha1_text | cut -c1-16)"
: >"$RUNTIME_LEDGER"

set +e
GSETX_TRANSACTION_ID="$transaction_id" GSETX_LEDGER="$RUNTIME_LEDGER" \
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
workers1_memory_kill="$(required_value "workers1_memory_kill" "$CLASSIFIER_OUT")"
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

runtime_field() {
  local row="$1"
  local key="$2"
  awk -F'\t' -v tx="$transaction_id" -v row="$row" -v key="$key" '
    $1 == "GSETX" && $2 == tx && $4 == row {
      for (i = 5; i <= NF; i++) {
        n = split($i, parts, " ")
        for (j = 1; j <= n; j++) {
          if (index(parts[j], key "=") == 1) {
            print substr(parts[j], length(key) + 2)
            found = 1
          }
        }
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$RUNTIME_LEDGER" 2>/dev/null | tail -1 || true
}

runtime_row_count() {
  local row="$1"
  awk -F'\t' -v tx="$transaction_id" -v row="$row" '
    $1 == "GSETX" && $2 == tx && $4 == row { count++ }
    END { print count + 0 }
  ' "$RUNTIME_LEDGER" 2>/dev/null || echo 0
}

runtime_field_for_mode() {
  local mode="$1"
  local row="$2"
  local key="$3"
  awk -F'\t' -v tx="$transaction_id" -v mode="$mode" -v row="$row" -v key="$key" '
    $1 == "GSETX" && $2 == tx && $3 == mode && $4 == row {
      for (i = 5; i <= NF; i++) {
        n = split($i, parts, " ")
        for (j = 1; j <= n; j++) {
          if (index(parts[j], key "=") == 1) {
            print substr(parts[j], length(key) + 2)
            found = 1
          }
        }
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$RUNTIME_LEDGER" 2>/dev/null | tail -1 || true
}

runtime_row_count_for_mode() {
  local mode="$1"
  local row="$2"
  awk -F'\t' -v tx="$transaction_id" -v mode="$mode" -v row="$row" '
    $1 == "GSETX" && $2 == tx && $3 == mode && $4 == row { count++ }
    END { print count + 0 }
  ' "$RUNTIME_LEDGER" 2>/dev/null || echo 0
}

runtime_hir_module_id="$(runtime_field "setup.hir_final" "hir_module_id")"
if [[ -z "$runtime_hir_module_id" ]]; then
  runtime_hir_module_id="$(runtime_field "setup.hir_module" "hir_module_id")"
fi
runtime_hir_functions="$(runtime_field "setup.hir_final" "hir_functions")"
runtime_mir_module_id="$(runtime_field "setup.mir_final" "mir_module_id")"
runtime_mir_functions="$(runtime_field "setup.mir_final" "mir_functions")"
runtime_session_id="$(runtime_field "llvm.session" "llvm_emission_session_id")"
runtime_planned_functions="$(runtime_field "llvm.session" "planned_functions")"
runtime_side_effect_phase="$(runtime_field "side_effect.runtime_counts" "phase")"
runtime_side_effect_emitted="$(runtime_field "side_effect.runtime_counts" "emitted")"
runtime_side_effect_called="$(runtime_field "side_effect.runtime_counts" "called")"
runtime_side_effect_undefined="$(runtime_field "side_effect.runtime_counts" "undefined")"
runtime_llvm_generate_phase="$(runtime_field "llvm.generate_phase" "phase")"
runtime_llvm_generate_out_pos="$(runtime_field "llvm.generate_phase" "out_pos")"
runtime_function_emission_phase="$(runtime_field "llvm.function_emission_phase" "phase")"
runtime_function_emission_mode="$(runtime_field "llvm.function_emission_phase" "mode")"
runtime_function_emission_out_pos="$(runtime_field "llvm.function_emission_phase" "out_pos")"
runtime_function_emission_index="$(runtime_field "llvm.function_emission_phase" "index")"
runtime_function_emission_total="$(runtime_field "llvm.function_emission_phase" "total_functions")"
runtime_default_function_emission_phase="$(runtime_field_for_mode "default_workers" "llvm.function_emission_phase" "phase")"
runtime_default_function_emission_mode="$(runtime_field_for_mode "default_workers" "llvm.function_emission_phase" "mode")"
runtime_default_function_emission_index="$(runtime_field_for_mode "default_workers" "llvm.function_emission_phase" "index")"
runtime_workers1_function_emission_phase="$(runtime_field_for_mode "workers1" "llvm.function_emission_phase" "phase")"
runtime_workers1_function_emission_mode="$(runtime_field_for_mode "workers1" "llvm.function_emission_phase" "mode")"
runtime_workers1_function_emission_index="$(runtime_field_for_mode "workers1" "llvm.function_emission_phase" "index")"
runtime_tail_phase="$(runtime_field "tail.semantic_split" "phase")"
runtime_output_rc="$(runtime_field "output.binary_compile_result" "rc")"
runtime_output_bytes="$(runtime_field "output.llvm_ir_written" "bytes")"
runtime_output_start_mode="$(runtime_field "output.llvm_ir_start" "emit_mode")"

if [[ -n "$runtime_side_effect_phase" ]]; then
  runtime_side_effect_row_counts="phase:${runtime_side_effect_phase},emitted:${runtime_side_effect_emitted:-missing},called:${runtime_side_effect_called:-missing},undefined:${runtime_side_effect_undefined:-missing}"
else
  runtime_side_effect_row_counts=""
fi

if [[ -n "$runtime_tail_phase" ]]; then
  runtime_tail_semantic_vs_input_split="runtime_tail:${runtime_tail_phase}"
elif [[ -n "$runtime_output_start_mode" ]]; then
  runtime_tail_semantic_vs_input_split="tail_not_reached_after_output_start"
else
  runtime_tail_semantic_vs_input_split=""
fi

if [[ -n "$runtime_output_rc" ]]; then
  runtime_output_commit_record="binary_compile_rc:${runtime_output_rc}"
elif [[ -n "$runtime_output_bytes" ]]; then
  runtime_output_commit_record="llvm_ir_written:${runtime_output_bytes}"
elif [[ -n "$runtime_output_start_mode" ]]; then
  runtime_output_commit_record="llvm_ir_started_without_commit:${runtime_output_start_mode}"
else
  runtime_output_commit_record=""
fi

case "$runtime_llvm_generate_phase" in
  "")
    runtime_llvm_generate_phase_split="llvm_generate_phase_unjoined"
    ;;
  generate_start)
    runtime_llvm_generate_phase_split="during_llvm_setup"
    ;;
  function_emission_start)
    runtime_llvm_generate_phase_split="during_function_emission"
    ;;
  function_emission_done)
    runtime_llvm_generate_phase_split="after_function_emission_before_tail"
    ;;
  tail_enter)
    runtime_llvm_generate_phase_split="during_tail"
    ;;
  tail_done)
    runtime_llvm_generate_phase_split="after_tail_before_metadata"
    ;;
  metadata_enter)
    runtime_llvm_generate_phase_split="during_metadata"
    ;;
  metadata_done)
    runtime_llvm_generate_phase_split="after_metadata_before_type_name_table"
    ;;
  type_name_table_enter)
    runtime_llvm_generate_phase_split="during_type_name_table"
    ;;
  type_name_table_done)
    runtime_llvm_generate_phase_split="after_type_name_table_before_dwarf"
    ;;
  dwarf_enter)
    runtime_llvm_generate_phase_split="during_dwarf"
    ;;
  dwarf_done)
    runtime_llvm_generate_phase_split="after_dwarf_before_finalize"
    ;;
  finalize_enter)
    runtime_llvm_generate_phase_split="during_finalize_setup"
    ;;
  finalize_to_s_enter)
    runtime_llvm_generate_phase_split="during_finalize_to_s"
    ;;
  finalize_to_s_done|finalize_external_done)
    runtime_llvm_generate_phase_split="generate_returned_to_cli"
    ;;
  *)
    runtime_llvm_generate_phase_split="unknown_llvm_generate_phase:${runtime_llvm_generate_phase}"
    ;;
esac

case "$runtime_function_emission_phase" in
  "")
    runtime_function_emission_split="function_emission_phase_unjoined"
    ;;
  dispatch_parallel|parallel_start|parallel_plan_done|parallel_workers_forked)
    runtime_function_emission_split="during_parallel_setup"
    ;;
  parallel_parent_emit_start|parallel_parent_emit_done)
    runtime_function_emission_split="during_parallel_parent_emit"
    ;;
  parallel_wait_start|parallel_wait_done)
    runtime_function_emission_split="during_parallel_worker_wait"
    ;;
  parallel_merge_start|parallel_merge_done)
    runtime_function_emission_split="during_parallel_merge"
    ;;
  parallel_cleanup_done)
    runtime_function_emission_split="after_parallel_cleanup"
    ;;
  parallel_rescue_fallback_sequential)
    runtime_function_emission_split="parallel_fallback_to_sequential"
    ;;
  dispatch_sequential|sequential_start|sequential_progress)
    runtime_function_emission_split="during_sequential_function_emit"
    ;;
  sequential_done)
    runtime_function_emission_split="after_sequential_function_emit"
    ;;
  *)
    runtime_function_emission_split="unknown_function_emission_phase:${runtime_function_emission_phase}"
    ;;
esac

runtime_default_function_emission_rows="$(runtime_row_count_for_mode "default_workers" "llvm.function_emission_phase")"
runtime_workers1_function_emission_rows="$(runtime_row_count_for_mode "workers1" "llvm.function_emission_phase")"
runtime_default_hir_final_rows="$(runtime_row_count_for_mode "default_workers" "setup.hir_final")"
runtime_workers1_hir_final_rows="$(runtime_row_count_for_mode "workers1" "setup.hir_final")"
runtime_default_mir_final_rows="$(runtime_row_count_for_mode "default_workers" "setup.mir_final")"
runtime_workers1_mir_final_rows="$(runtime_row_count_for_mode "workers1" "setup.mir_final")"
runtime_default_output_start_rows="$(runtime_row_count_for_mode "default_workers" "output.llvm_ir_start")"
runtime_workers1_output_start_rows="$(runtime_row_count_for_mode "workers1" "output.llvm_ir_start")"
runtime_default_llvm_generate_rows="$(runtime_row_count_for_mode "default_workers" "llvm.generate_phase")"
runtime_workers1_llvm_generate_rows="$(runtime_row_count_for_mode "workers1" "llvm.generate_phase")"
if [[ "$runtime_default_function_emission_rows" -gt 0 && "$runtime_workers1_function_emission_rows" -gt 0 ]]; then
  runtime_function_emission_mode_join="both_modes"
elif [[ "$runtime_default_function_emission_rows" -gt 0 ]]; then
  runtime_function_emission_mode_join="default_only"
elif [[ "$runtime_workers1_function_emission_rows" -gt 0 ]]; then
  runtime_function_emission_mode_join="workers1_only"
else
  runtime_function_emission_mode_join="unjoined"
fi

mode_boundary_from_rows() {
  local hir_rows="$1"
  local mir_rows="$2"
  local output_rows="$3"
  local llvm_rows="$4"
  local function_rows="$5"

  if [[ "$function_rows" -gt 0 ]]; then
    echo "reached_function_emission"
  elif [[ "$llvm_rows" -gt 0 ]]; then
    echo "after_llvm_generate_start_before_function_emission"
  elif [[ "$output_rows" -gt 0 ]]; then
    echo "after_output_start_before_llvm_generate"
  elif [[ "$mir_rows" -gt 0 ]]; then
    echo "after_mir_final_before_output_start"
  elif [[ "$hir_rows" -gt 0 ]]; then
    echo "after_hir_final_before_mir_final"
  else
    echo "before_hir_final_or_unjoined"
  fi
}

runtime_default_mode_boundary="$(
  mode_boundary_from_rows \
    "$runtime_default_hir_final_rows" \
    "$runtime_default_mir_final_rows" \
    "$runtime_default_output_start_rows" \
    "$runtime_default_llvm_generate_rows" \
    "$runtime_default_function_emission_rows"
)"
runtime_workers1_mode_boundary="$(
  mode_boundary_from_rows \
    "$runtime_workers1_hir_final_rows" \
    "$runtime_workers1_mir_final_rows" \
    "$runtime_workers1_output_start_rows" \
    "$runtime_workers1_llvm_generate_rows" \
    "$runtime_workers1_function_emission_rows"
)"

missing_runtime_rows=()
[[ -z "$runtime_hir_module_id" ]] && missing_runtime_rows+=("hir_module_id")
[[ -z "$runtime_mir_module_id" ]] && missing_runtime_rows+=("mir_module_id")
[[ -z "$runtime_session_id" ]] && missing_runtime_rows+=("llvm_emission_session_id")
[[ -z "$runtime_side_effect_row_counts" ]] && missing_runtime_rows+=("runtime_side_effect_row_counts")
[[ -z "$runtime_tail_semantic_vs_input_split" ]] && missing_runtime_rows+=("tail_semantic_vs_input_split")
[[ -z "$runtime_output_commit_record" ]] && missing_runtime_rows+=("output_commit_record")

runtime_joined=0
if [[ ${#missing_runtime_rows[@]} -eq 0 ]]; then
  runtime_joined=1
fi

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
  if [[ $runtime_joined -eq 1 ]]; then
    admission_status="rejected_no_root_sized_consumer"
    join_status="joined"
  else
    admission_status="candidate_clean_requires_joined_runtime_rows"
    join_status="phase_local_only"
  fi
elif [[ "$b4_classification" == "current_0k_bn_frontier" ]]; then
  if [[ $runtime_joined -eq 1 ]]; then
    if [[ "$default_workers_memory_kill" == "1" ]]; then
      final_classification="abort_resource"
    elif [[ "$workers1_exit139" == "1" ]]; then
      final_classification="abort_signal"
    else
      final_classification="abort_joined_current_frontier"
    fi
    admission_status="rejected_no_root_sized_consumer"
    join_status="joined"
  else
    final_classification="abort_unjoined_evidence"
    admission_status="rejected_unjoined_evidence"
    join_status="phase_local_only"
  fi
elif [[ "$b4_classification" == "llvm_entry_failure_after_lower_main" ]]; then
  if [[ $runtime_joined -eq 1 ]]; then
    if [[ "$default_workers_memory_kill" == "1" || "$workers1_memory_kill" == "1" ]]; then
      final_classification="abort_resource_after_lower_main"
    else
      final_classification="abort_after_lower_main_unclassified"
    fi
    admission_status="rejected_no_root_sized_consumer"
    join_status="joined"
  else
    final_classification="abort_unjoined_evidence"
    admission_status="rejected_unjoined_evidence"
    join_status="phase_local_only"
  fi
else
  if [[ $runtime_joined -eq 1 ]]; then
    final_classification="abort_joined_unclassified"
    admission_status="rejected_no_root_sized_consumer"
    join_status="joined"
  else
    final_classification="abort_unjoined_evidence"
    admission_status="rejected_unjoined_evidence"
    join_status="phase_local_only"
  fi
fi

if [[ "$join_status" == "phase_local_only" ]]; then
  if [[ ${#missing_runtime_rows[@]} -gt 0 ]]; then
    missing_joined="$(IFS=,; echo "${missing_runtime_rows[*]}")"
    unjoined_reason="missing_runtime_transaction_rows:${missing_joined}"
  else
    unjoined_reason="missing_runtime_transaction_rows:unknown"
  fi
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
echo "require_post_cu_resource=${REQUIRE_POST_CU_RESOURCE:-0}"
echo "require_resource_phase_split=${REQUIRE_RESOURCE_PHASE_SPLIT:-0}"
echo "require_function_emission_split=${REQUIRE_FUNCTION_EMISSION_SPLIT:-0}"
echo "require_worker_mode_boundary=${REQUIRE_WORKER_MODE_BOUNDARY:-0}"
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
echo "setup.runtime_hir_module_id=${runtime_hir_module_id:-unjoined}"
echo "setup.runtime_hir_functions=${runtime_hir_functions:-unjoined}"
echo "setup.runtime_mir_module_id=${runtime_mir_module_id:-unjoined}"
echo "setup.runtime_mir_functions=${runtime_mir_functions:-unjoined}"
echo "setup.runtime_session_id=${runtime_session_id:-unjoined}"
echo "function_plan.source_status=$source_shape"
echo "function_plan.runtime_plan_rows=${runtime_planned_functions:-unjoined}"
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
echo "side_effect.runtime_row_counts=${runtime_side_effect_row_counts:-unjoined}"
echo "tail.default_parallel_rand=$default_workers_parallel_rand"
echo "tail.workers1_exit139=$workers1_exit139"
echo "tail.semantic_vs_input_split=${runtime_tail_semantic_vs_input_split:-unjoined}"
echo "output.default_binary_present=$default_workers_binary_present"
echo "output.workers1_binary_present=$workers1_binary_present"
echo "output.commit_record=${runtime_output_commit_record:-unjoined}"
echo "resource.default_memory_kill=$default_workers_memory_kill"
echo "resource.workers1_memory_kill=$workers1_memory_kill"
echo "resource.workers1_exit139=$workers1_exit139"
echo "resource.worker_mode_split=default_vs_workers1"
echo "resource.llvm_generate_last_phase=${runtime_llvm_generate_phase:-unjoined}"
echo "resource.llvm_generate_last_out_pos=${runtime_llvm_generate_out_pos:-unjoined}"
echo "resource.llvm_generate_phase_split=$runtime_llvm_generate_phase_split"
echo "resource.function_emission_last_phase=${runtime_function_emission_phase:-unjoined}"
echo "resource.function_emission_last_mode=${runtime_function_emission_mode:-unjoined}"
echo "resource.function_emission_last_index=${runtime_function_emission_index:-unjoined}"
echo "resource.function_emission_last_total=${runtime_function_emission_total:-unjoined}"
echo "resource.function_emission_last_out_pos=${runtime_function_emission_out_pos:-unjoined}"
echo "resource.function_emission_split=$runtime_function_emission_split"
echo "resource.function_emission_mode_join_status=$runtime_function_emission_mode_join"
echo "resource.default_function_emission_last_phase=${runtime_default_function_emission_phase:-unjoined}"
echo "resource.default_function_emission_last_mode=${runtime_default_function_emission_mode:-unjoined}"
echo "resource.default_function_emission_last_index=${runtime_default_function_emission_index:-unjoined}"
echo "resource.workers1_function_emission_last_phase=${runtime_workers1_function_emission_phase:-unjoined}"
echo "resource.workers1_function_emission_last_mode=${runtime_workers1_function_emission_mode:-unjoined}"
echo "resource.workers1_function_emission_last_index=${runtime_workers1_function_emission_index:-unjoined}"
echo "resource.default_mode_boundary=$runtime_default_mode_boundary"
echo "resource.workers1_mode_boundary=$runtime_workers1_mode_boundary"
echo "runtime.ledger_rows=$(awk -F'\t' -v tx="$transaction_id" '$1 == "GSETX" && $2 == tx { count++ } END { print count + 0 }' "$RUNTIME_LEDGER" 2>/dev/null || echo 0)"
echo "runtime.hir_rows=$(runtime_row_count "setup.hir_final")"
echo "runtime.mir_rows=$(runtime_row_count "setup.mir_final")"
echo "runtime.session_rows=$(runtime_row_count "llvm.session")"
echo "runtime.side_effect_rows=$(runtime_row_count "side_effect.runtime_counts")"
echo "runtime.llvm_generate_phase_rows=$(runtime_row_count "llvm.generate_phase")"
echo "runtime.function_emission_phase_rows=$(runtime_row_count "llvm.function_emission_phase")"
echo "runtime.default_hir_final_rows=$runtime_default_hir_final_rows"
echo "runtime.workers1_hir_final_rows=$runtime_workers1_hir_final_rows"
echo "runtime.default_mir_final_rows=$runtime_default_mir_final_rows"
echo "runtime.workers1_mir_final_rows=$runtime_workers1_mir_final_rows"
echo "runtime.default_output_start_rows=$runtime_default_output_start_rows"
echo "runtime.workers1_output_start_rows=$runtime_workers1_output_start_rows"
echo "runtime.default_llvm_generate_phase_rows=$runtime_default_llvm_generate_rows"
echo "runtime.workers1_llvm_generate_phase_rows=$runtime_workers1_llvm_generate_rows"
echo "runtime.default_function_emission_phase_rows=$runtime_default_function_emission_rows"
echo "runtime.workers1_function_emission_phase_rows=$runtime_workers1_function_emission_rows"
echo "runtime.tail_rows=$(runtime_row_count "tail.semantic_split")"
echo "runtime.output_rows=$(( $(runtime_row_count "output.llvm_ir_start") + $(runtime_row_count "output.llvm_ir_written") + $(runtime_row_count "output.binary_compile_result") ))"
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
if [[ "${REQUIRE_POST_CU_RESOURCE:-0}" == "1" &&
      "$final_classification" != "abort_resource_after_lower_main" ]]; then
  exit_code=9
fi
if [[ "${REQUIRE_RESOURCE_PHASE_SPLIT:-0}" == "1" &&
      "$runtime_llvm_generate_phase_split" == "llvm_generate_phase_unjoined" ]]; then
  exit_code=9
fi
if [[ "${REQUIRE_FUNCTION_EMISSION_SPLIT:-0}" == "1" &&
      "$runtime_function_emission_split" == "function_emission_phase_unjoined" ]]; then
  exit_code=9
fi
if [[ "${REQUIRE_WORKER_MODE_BOUNDARY:-0}" == "1" &&
      ( "$runtime_default_mode_boundary" == "before_hir_final_or_unjoined" ||
        "$runtime_workers1_mode_boundary" == "before_hir_final_or_unjoined" ) ]]; then
  exit_code=9
fi
if [[ "${REQUIRE_ADMIT_BEHAVIOR:-0}" == "1" && "$admission_status" != "admit_behavior_candidate" ]]; then
  exit_code=9
fi

exit "$exit_code"
