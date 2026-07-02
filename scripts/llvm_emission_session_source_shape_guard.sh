#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/mir/llvm_backend.cr"

REQUIRE_SESSION="${REQUIRE_SESSION:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/llvm_emission_session_source_shape_guard.sh
env:
  REQUIRE_SESSION=0|1

Behavior-neutral source-shape guard for Slice 0k-BQ. It verifies that the
generated-stage LLVM entry has a concrete LLVMEmissionSession owner record and
that LLVMIRGenerator#generate consumes the function-list plan through that
session instead of keeping the reachability/skip/dedup authority only as inline
locals in generate.
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

echo "# LLVMEmissionSession Source Shape Guard"
echo "source=$SOURCE_FILE"
echo "require_session=$REQUIRE_SESSION"
echo "source_shape=$source_shape"
echo "session_owner_type_count=$(( $(count_literal "record LLVMEmissionSession") + $(count_literal "class LLVMEmissionSession") ))"
echo "function_plan_owner_type_count=$(( $(count_literal "record LLVMEmissionFunctionPlan") + $(count_literal "class LLVMEmissionFunctionPlan") ))"
echo "session_builder_count=$(count_literal "private def build_llvm_emission_session")"
echo "function_plan_builder_count=$(count_literal "private def build_llvm_emission_function_plan")"
echo "generate_builds_session_count=$(count_literal "emission_session = build_llvm_emission_session")"
echo "generate_consumes_functions_count=$(count_literal "functions_to_emit = emission_session.functions_to_emit")"
echo "generate_inline_reachability_count=$(count_in_generate "functions_to_emit = if @reachability")"
echo "generate_inline_skip_set_count=$(count_in_generate "skip_ids = ::Set(FunctionId).new")"
echo "generate_inline_dedup_count=$(count_in_generate "dedup_seen = ::Set(String).new")"
echo "global_reachability_plan_count=$(count_literal "functions_to_emit = if @reachability")"
echo "global_skip_set_count=$(count_literal "skip_ids = ::Set(FunctionId).new")"
echo "global_dedup_count=$(count_literal "dedup_seen = ::Set(String).new")"

if [[ "$REQUIRE_SESSION" == "1" && "$source_shape" != "session_consumes_function_plan" ]]; then
  echo "FAIL: LLVMEmissionSession does not yet consume the function-list authority edge" >&2
  exit 1
fi
