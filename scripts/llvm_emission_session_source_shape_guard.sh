#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/mir/llvm_backend.cr"

REQUIRE_SESSION="${REQUIRE_SESSION:-0}"
REQUIRE_WORKER_PLAN="${REQUIRE_WORKER_PLAN:-0}"
REQUIRE_SIDE_EFFECT_CONTRACT="${REQUIRE_SIDE_EFFECT_CONTRACT:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/llvm_emission_session_source_shape_guard.sh
env:
  REQUIRE_SESSION=0|1
  REQUIRE_WORKER_PLAN=0|1
  REQUIRE_SIDE_EFFECT_CONTRACT=0|1

Behavior-neutral source-shape guard for Slices 0k-BQ/0k-BR/0k-BS. It verifies that the
generated-stage LLVM entry has a concrete LLVMEmissionSession owner record and
that LLVMIRGenerator#generate consumes the function-list plan through that
session instead of keeping the reachability/skip/dedup authority only as inline
locals in generate. With REQUIRE_WORKER_PLAN=1 it also verifies that generate
consumes the effective LLVM worker policy through the session instead of
computing parallel_llvm_workers / debug-info sequential override inline.
With REQUIRE_SIDE_EFFECT_CONTRACT=1 it verifies that emit_functions_parallel
delegates worker side-effect writing and parent side-effect merging through a
session-owned contract instead of owning raw .se row tags and the merge switch
inline.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

count_literal() {
  local pattern="$1"
  grep -F -c "$pattern" "$SOURCE_FILE" || true
}

count_in_generate() {
  local pattern="$1"
  awk -v pat="$pattern" '
    /def generate/ {
      in_generate = 1
      next
    }
    in_generate && /private def / {
      in_generate = 0
    }
    in_generate && index($0, pat) > 0 {
      count++
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
}

count_in_emit_functions_parallel() {
  local pattern="$1"
  awk -v pat="$pattern" '
    /private def emit_functions_parallel/ {
      in_method = 1
      next
    }
    in_method && /private def / {
      in_method = 0
    }
    in_method && index($0, pat) > 0 {
      count++
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
}

source_shape="$(
  awk '
    /record LLVMEmissionFunctionPlan|class LLVMEmissionFunctionPlan/ { has_function_plan_record = 1 }
    /record LLVMEmissionSession|class LLVMEmissionSession/ { has_session_record = 1 }
    /private def build_llvm_emission_session/ { has_session_builder = 1 }
    /private def build_llvm_emission_function_plan/ { has_function_plan_builder = 1 }

    /def generate/ {
      in_generate = 1
      next
    }
    in_generate && /private def / {
      in_generate = 0
    }
    in_generate {
      if (index($0, "emission_session = build_llvm_emission_session") > 0) {
        generate_builds_session = 1
      }
      if (index($0, "functions_to_emit = emission_session.functions_to_emit") > 0) {
        generate_consumes_session_functions = 1
      }
      if (index($0, "functions_to_emit = if @reachability") > 0) {
        generate_inline_reachability = 1
      }
      if (index($0, "skip_ids = ::Set(FunctionId).new") > 0) {
        generate_inline_skip_set = 1
      }
      if (index($0, "dedup_seen = ::Set(String).new") > 0) {
        generate_inline_dedup = 1
      }
    }

    END {
      if (has_function_plan_record &&
          has_session_record &&
          has_session_builder &&
          has_function_plan_builder &&
          generate_builds_session &&
          generate_consumes_session_functions &&
          !generate_inline_reachability &&
          !generate_inline_skip_set &&
          !generate_inline_dedup) {
        print "session_consumes_function_plan"
      } else if (has_session_record || has_session_builder || generate_builds_session) {
        print "partial_session_authority"
      } else {
        print "legacy_inline_function_plan"
      }
    }
  ' "$SOURCE_FILE"
)"

worker_shape="$(
  awk '
    /class LLVMEmissionWorkerPlan|def worker_sequential_reason_code/ { has_worker_plan_record = 1 }
    /private def build_llvm_emission_worker_plan/ { has_worker_plan_builder = 1 }

    /def generate/ {
      in_generate = 1
      next
    }
    in_generate && /private def / {
      in_generate = 0
    }
    in_generate {
      if (index($0, "n_workers = emission_session.effective_worker_count") > 0) {
        generate_consumes_worker_plan = 1
      }
      if (index($0, "n_workers = parallel_llvm_workers") > 0) {
        generate_inline_worker_count = 1
      }
      if (index($0, "n_workers = 1 if @debug_emit_anchors") > 0) {
        generate_inline_debug_override = 1
      }
    }

    END {
      if (has_worker_plan_record &&
          has_worker_plan_builder &&
          generate_consumes_worker_plan &&
          !generate_inline_worker_count &&
          !generate_inline_debug_override) {
        print "session_consumes_worker_plan"
      } else if (has_worker_plan_record || has_worker_plan_builder || generate_consumes_worker_plan) {
        print "partial_worker_plan_authority"
      } else {
        print "legacy_inline_worker_policy"
      }
    }
  ' "$SOURCE_FILE"
)"

side_effect_contract_shape="$(
  awk '
    /def side_effect_string_constant_tag/ { has_tag_schema = 1 }
    /private def write_worker_side_effects_with_contract\(emission_session : LLVMEmissionSession/ { has_writer_helper = 1 }
    /private def merge_worker_side_effects_with_contract\(emission_session : LLVMEmissionSession/ { has_merge_helper = 1 }

    /private def emit_functions_parallel/ {
      in_parallel = 1
      next
    }
    in_parallel && /private def / {
      in_parallel = 0
    }
    in_parallel {
      if (index($0, "write_worker_side_effects_with_contract(emission_session, se_file)") > 0) {
        calls_writer_helper = 1
      }
      if (index($0, "max_string_counter = merge_worker_side_effects_with_contract(emission_session, se_file, max_string_counter)") > 0) {
        calls_merge_helper = 1
      }
      if (index($0, "f.puts \"STR") > 0 ||
          index($0, "f.puts \"ZSG") > 0 ||
          index($0, "f.puts \"EXT") > 0 ||
          index($0, "f.puts \"CCF") > 0 ||
          index($0, "f.puts \"EMF") > 0 ||
          index($0, "f.puts \"ERT") > 0 ||
          index($0, "f.puts \"MSG") > 0 ||
          index($0, "f.puts \"DGF") > 0 ||
          index($0, "f.puts \"SCN") > 0) {
        raw_writer_tags = 1
      }
      if (index($0, "when \"STR\"") > 0 ||
          index($0, "when \"ZSG\"") > 0 ||
          index($0, "when \"EXT\"") > 0 ||
          index($0, "when \"CCF\"") > 0 ||
          index($0, "when \"EMF\"") > 0 ||
          index($0, "when \"ERT\"") > 0 ||
          index($0, "when \"MSG\"") > 0 ||
          index($0, "when \"DGF\"") > 0 ||
          index($0, "when \"SCN\"") > 0) {
        raw_merge_tags = 1
      }
    }

    END {
      if (has_tag_schema &&
          has_writer_helper &&
          has_merge_helper &&
          calls_writer_helper &&
          calls_merge_helper &&
          !raw_writer_tags &&
          !raw_merge_tags) {
        print "session_consumes_side_effect_merge_contract"
      } else if (has_tag_schema || has_writer_helper || has_merge_helper || calls_writer_helper || calls_merge_helper) {
        print "partial_side_effect_merge_contract"
      } else {
        print "legacy_parallel_side_effect_merge"
      }
    }
  ' "$SOURCE_FILE"
)"

echo "# LLVMEmissionSession Source Shape Guard"
echo "source=$SOURCE_FILE"
echo "require_session=$REQUIRE_SESSION"
echo "require_worker_plan=$REQUIRE_WORKER_PLAN"
echo "require_side_effect_contract=$REQUIRE_SIDE_EFFECT_CONTRACT"
echo "source_shape=$source_shape"
echo "worker_shape=$worker_shape"
echo "side_effect_contract_shape=$side_effect_contract_shape"
echo "session_owner_type_count=$(( $(count_literal "record LLVMEmissionSession") + $(count_literal "class LLVMEmissionSession") ))"
echo "function_plan_owner_type_count=$(( $(count_literal "record LLVMEmissionFunctionPlan") + $(count_literal "class LLVMEmissionFunctionPlan") ))"
echo "worker_plan_owner_surface_count=$(( $(count_literal "class LLVMEmissionWorkerPlan") + $(count_literal "def worker_sequential_reason_code") ))"
echo "side_effect_tag_schema_count=$(count_literal "def side_effect_string_constant_tag")"
echo "side_effect_writer_helper_count=$(count_literal "private def write_worker_side_effects_with_contract")"
echo "side_effect_merge_helper_count=$(count_literal "private def merge_worker_side_effects_with_contract")"
echo "session_builder_count=$(count_literal "private def build_llvm_emission_session")"
echo "function_plan_builder_count=$(count_literal "private def build_llvm_emission_function_plan")"
echo "worker_plan_builder_count=$(count_literal "private def build_llvm_emission_worker_plan")"
echo "generate_builds_session_count=$(count_literal "emission_session = build_llvm_emission_session")"
echo "generate_consumes_functions_count=$(count_literal "functions_to_emit = emission_session.functions_to_emit")"
echo "generate_consumes_worker_count=$(count_literal "n_workers = emission_session.effective_worker_count")"
echo "generate_inline_reachability_count=$(count_in_generate "functions_to_emit = if @reachability")"
echo "generate_inline_skip_set_count=$(count_in_generate "skip_ids = ::Set(FunctionId).new")"
echo "generate_inline_dedup_count=$(count_in_generate "dedup_seen = ::Set(String).new")"
echo "generate_inline_worker_count=$(count_in_generate "n_workers = parallel_llvm_workers")"
echo "generate_inline_debug_override_count=$(count_in_generate "n_workers = 1 if @debug_emit_anchors")"
echo "global_reachability_plan_count=$(count_literal "functions_to_emit = if @reachability")"
echo "global_skip_set_count=$(count_literal "skip_ids = ::Set(FunctionId).new")"
echo "global_dedup_count=$(count_literal "dedup_seen = ::Set(String).new")"
echo "global_parallel_worker_count=$(count_literal "parallel_llvm_workers")"
echo "parallel_contract_writer_call_count=$(count_in_emit_functions_parallel "write_worker_side_effects_with_contract(emission_session, se_file)")"
echo "parallel_contract_merge_call_count=$(count_in_emit_functions_parallel "max_string_counter = merge_worker_side_effects_with_contract(emission_session, se_file, max_string_counter)")"
echo "parallel_raw_side_effect_writer_tags=$(( $(count_in_emit_functions_parallel "f.puts \"STR") + $(count_in_emit_functions_parallel "f.puts \"ZSG") + $(count_in_emit_functions_parallel "f.puts \"EXT") + $(count_in_emit_functions_parallel "f.puts \"CCF") + $(count_in_emit_functions_parallel "f.puts \"EMF") + $(count_in_emit_functions_parallel "f.puts \"ERT") + $(count_in_emit_functions_parallel "f.puts \"MSG") + $(count_in_emit_functions_parallel "f.puts \"DGF") + $(count_in_emit_functions_parallel "f.puts \"SCN") ))"
echo "parallel_raw_side_effect_merge_tags=$(( $(count_in_emit_functions_parallel "when \"STR\"") + $(count_in_emit_functions_parallel "when \"ZSG\"") + $(count_in_emit_functions_parallel "when \"EXT\"") + $(count_in_emit_functions_parallel "when \"CCF\"") + $(count_in_emit_functions_parallel "when \"EMF\"") + $(count_in_emit_functions_parallel "when \"ERT\"") + $(count_in_emit_functions_parallel "when \"MSG\"") + $(count_in_emit_functions_parallel "when \"DGF\"") + $(count_in_emit_functions_parallel "when \"SCN\"") ))"

if [[ "$REQUIRE_SESSION" == "1" && "$source_shape" != "session_consumes_function_plan" ]]; then
  echo "FAIL: LLVMEmissionSession does not yet consume the function-list authority edge" >&2
  exit 1
fi

if [[ "$REQUIRE_WORKER_PLAN" == "1" && "$worker_shape" != "session_consumes_worker_plan" ]]; then
  echo "FAIL: LLVMEmissionSession does not yet consume the worker-policy authority edge" >&2
  exit 1
fi

if [[ "$REQUIRE_SIDE_EFFECT_CONTRACT" == "1" && "$side_effect_contract_shape" != "session_consumes_side_effect_merge_contract" ]]; then
  echo "FAIL: LLVMEmissionSession does not yet consume the side-effect merge contract edge" >&2
  exit 1
fi
