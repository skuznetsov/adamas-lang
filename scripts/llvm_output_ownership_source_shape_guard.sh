#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/mir/llvm_backend.cr"

REQUIRE_OUTPUT_OWNERSHIP="${REQUIRE_OUTPUT_OWNERSHIP:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/llvm_output_ownership_source_shape_guard.sh
env:
  REQUIRE_OUTPUT_OWNERSHIP=0|1

Behavior-neutral source-shape guard for the post-0k-EJ OutputOwnershipContract
slice. Current HEAD is expected to report legacy ambient output restore: the
primary LLVM output sink is still represented by mutable @output plus local
saved_output snapshots inside temporary-output regions.

With REQUIRE_OUTPUT_OWNERSHIP=1, this guard requires a concrete
LLVMOutputOwnershipContract owner surface and verifies that emit_functions_parallel
uses that owner for rescue restore instead of restoring a local saved_output
binding directly.
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

count_in_method() {
  local method="$1"
  local pattern="$2"
  awk -v method="$method" -v pat="$pattern" '
    index($0, "private def " method) > 0 || index($0, "def " method) > 0 {
      in_method = 1
      next
    }
    in_method && /private def |^[[:space:]]*def / {
      in_method = 0
    }
    in_method && index($0, pat) > 0 {
      count++
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
}

output_ownership_shape="$(
  awk '
    /class LLVMOutputOwnershipContract|record LLVMOutputOwnershipContract/ {
      has_contract_type = 1
    }
    /def primary_output|def current_output|def capture_primary_output/ {
      has_primary_owner_api = 1
    }
    /def with_temporary_output|def enter_temporary_output|def restore_primary_output/ {
      has_restore_api = 1
    }

    /private def emit_functions_parallel/ {
      in_parallel = 1
      next
    }
    in_parallel && /private def / {
      in_parallel = 0
    }
    in_parallel {
      if (index($0, "output_ownership.") > 0 ||
          index($0, "OutputOwnership") > 0 ||
          index($0, "restore_primary_output") > 0 ||
          index($0, "with_temporary_output") > 0) {
        parallel_uses_contract = 1
      }
      if (index($0, "saved_output = @output") > 0) {
        parallel_direct_saved_output = 1
      }
      if (index($0, "@output = saved_output if saved_output") > 0 ||
          index($0, "@output = saved_output") > 0) {
        parallel_direct_restore = 1
      }
    }

    END {
      if (has_contract_type &&
          has_primary_owner_api &&
          has_restore_api &&
          parallel_uses_contract &&
          !parallel_direct_restore) {
        print "output_ownership_contract_consumed_by_parallel_restore"
      } else if (has_contract_type || has_primary_owner_api || has_restore_api || parallel_uses_contract) {
        print "partial_output_ownership_contract"
      } else {
        print "legacy_ambient_output_restore"
      }
    }
  ' "$SOURCE_FILE"
)"

echo "# LLVM Output Ownership Source Shape Guard"
echo "source=$SOURCE_FILE"
echo "require_output_ownership=$REQUIRE_OUTPUT_OWNERSHIP"
echo "output_ownership_shape=$output_ownership_shape"
echo "output_contract_type_count=$(( $(count_literal "class LLVMOutputOwnershipContract") + $(count_literal "record LLVMOutputOwnershipContract") ))"
echo "output_contract_primary_api_count=$(( $(count_literal "def primary_output") + $(count_literal "def current_output") + $(count_literal "def capture_primary_output") ))"
echo "output_contract_restore_api_count=$(( $(count_literal "def with_temporary_output") + $(count_literal "def enter_temporary_output") + $(count_literal "def restore_primary_output") ))"
echo "parallel_saved_output_snapshot_count=$(count_in_method "emit_functions_parallel" "saved_output = @output")"
echo "parallel_direct_saved_output_restore_count=$(( $(count_in_method "emit_functions_parallel" "@output = saved_output if saved_output") + $(count_in_method "emit_functions_parallel" "@output = saved_output") ))"
echo "parallel_output_ownership_reference_count=$(( $(count_in_method "emit_functions_parallel" "output_ownership.") + $(count_in_method "emit_functions_parallel" "OutputOwnership") + $(count_in_method "emit_functions_parallel" "restore_primary_output") + $(count_in_method "emit_functions_parallel" "with_temporary_output") ))"
echo "metadata_saved_output_snapshot_count=$(count_in_method "generate" "saved_output = @output")"
echo "metadata_direct_restore_count=$(count_in_method "generate" "@output = saved_output")"
echo "function_block_saved_output_snapshot_count=$(count_literal "saved_output = @output")"
echo "function_block_direct_restore_count=$(count_literal "@output = saved_output")"

if [[ "$REQUIRE_OUTPUT_OWNERSHIP" == "1" &&
      "$output_ownership_shape" != "output_ownership_contract_consumed_by_parallel_restore" ]]; then
  echo "FAIL: LLVM output restore is still governed by ambient @output/local saved_output state" >&2
  exit 1
fi
