#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/cli.cr"

REQUIRE_OUTPUT_OUTCOME="${REQUIRE_OUTPUT_OUTCOME:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/generated_stage_outcome_source_shape_guard.sh
env:
  REQUIRE_OUTPUT_OUTCOME=0|1

Behavior-neutral source-shape guard for the 0k-CH/0k-CJ output-owner checkpoint.
It verifies that the CLI output commit-record edge is owned by a
GeneratedStageExecutionOutcome helper: the output.llvm_ir_start,
output.llvm_ir_written, and output.binary_compile_result GSETX rows must be
serialized through the outcome helper instead of being emitted directly from
scattered CLI step locals.
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

count_outside_outcome_helpers() {
  local pattern="$1"
  awk -v pat="$pattern" '
    /^[[:space:]]*private def log_generated_stage_outcome_/ {
      in_helper = 1
      next
    }
    in_helper && /^[[:space:]]*end[[:space:]]*$/ {
      in_helper = 0
      next
    }
    !in_helper && index($0, pat) > 0 {
      count++
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
}

owner_type_count="$(( $(count_literal "class GeneratedStageExecutionOutcome") + $(count_literal "struct GeneratedStageExecutionOutcome") + $(count_literal "record GeneratedStageExecutionOutcome") ))"
outcome_new_count="$(count_literal "GeneratedStageExecutionOutcome.new")"
start_helper_count="$(count_literal "private def log_generated_stage_outcome_llvm_ir_start")"
written_helper_count="$(count_literal "private def log_generated_stage_outcome_llvm_ir_written")"
compile_helper_count="$(count_literal "private def log_generated_stage_outcome_binary_compile_result")"

start_helper_calls="$(count_literal "log_generated_stage_outcome_llvm_ir_start(output_outcome)")"
written_helper_calls="$(count_literal "log_generated_stage_outcome_llvm_ir_written(output_outcome)")"
compile_helper_calls="$(count_literal "log_generated_stage_outcome_binary_compile_result(output_outcome)")"

direct_output_start_rows="$(count_outside_outcome_helpers '"output.llvm_ir_start"')"
direct_output_written_rows="$(count_outside_outcome_helpers '"output.llvm_ir_written"')"
direct_binary_result_rows="$(count_outside_outcome_helpers '"output.binary_compile_result"')"

source_shape="legacy_direct_output_commit_rows"
if (( owner_type_count == 1 &&
      outcome_new_count >= 1 &&
      start_helper_count == 1 &&
      written_helper_count == 1 &&
      compile_helper_count == 1 &&
      start_helper_calls == 2 &&
      written_helper_calls == 2 &&
      compile_helper_calls == 1 &&
      direct_output_start_rows == 0 &&
      direct_output_written_rows == 0 &&
      direct_binary_result_rows == 0 )); then
  source_shape="outcome_serializes_output_commit_rows"
elif (( owner_type_count > 0 || start_helper_count > 0 || written_helper_count > 0 || compile_helper_count > 0 )); then
  source_shape="partial_generated_stage_outcome_output_rows"
fi

echo "# GeneratedStageExecutionOutcome Source Shape Guard"
echo "source=$SOURCE_FILE"
echo "require_output_outcome=$REQUIRE_OUTPUT_OUTCOME"
echo "source_shape=$source_shape"
echo "owner_type_count=$owner_type_count"
echo "outcome_new_count=$outcome_new_count"
echo "start_helper_count=$start_helper_count"
echo "written_helper_count=$written_helper_count"
echo "compile_helper_count=$compile_helper_count"
echo "start_helper_calls=$start_helper_calls"
echo "written_helper_calls=$written_helper_calls"
echo "compile_helper_calls=$compile_helper_calls"
echo "direct_output_start_rows=$direct_output_start_rows"
echo "direct_output_written_rows=$direct_output_written_rows"
echo "direct_binary_result_rows=$direct_binary_result_rows"

if [[ "$REQUIRE_OUTPUT_OUTCOME" == "1" && "$source_shape" != "outcome_serializes_output_commit_rows" ]]; then
  echo "FAIL: GeneratedStageExecutionOutcome does not own CLI output commit-record rows" >&2
  exit 1
fi

echo "PASS: GeneratedStageExecutionOutcome source-shape status=$source_shape"
