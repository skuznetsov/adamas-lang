#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
REQUIRE_PROVEN_RETURN_TYPE="${REQUIRE_PROVEN_RETURN_TYPE:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/nested_module_return_type_provenance_source_shape_guard.sh
env:
  REQUIRE_PROVEN_RETURN_TYPE=0|1

Source-shape guard for nested-module return-type provenance. The registration
path must pass one proven non-null TypeRef binding into its strict return-type
contracts instead of leaking the optional accumulator across the namespace
block boundary.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

report="$(
  awk '
    /private def register_nested_module_in_current_arena\(/ {
      in_helper = 1
      next
    }

    in_helper && /^    (private )?def / {
      in_helper = 0
    }

    in_helper {
      if ($0 ~ /resolved_return_type = return_type \|\| TypeRef::VOID/) {
        proof_bindings++
      }
      if ($0 ~ /record_explicit_return_contract\(/) {
        in_contract = 1
      }
      if (in_contract && $0 ~ /^[[:space:]]+resolved_return_type,$/) {
        proven_contract_consumers++
        in_contract = 0
      } else if (in_contract && $0 ~ /^[[:space:]]+return_type,$/) {
        optional_contract_consumers++
        in_contract = 0
      }
      if ($0 ~ /register_function_type\(/) {
        in_register = 1
      }
      if (in_register && $0 ~ /^[[:space:]]+resolved_return_type,$/) {
        proven_register_consumers++
        in_register = 0
      } else if (in_register && $0 ~ /^[[:space:]]+return_type,$/) {
        optional_register_consumers++
        in_register = 0
      }
    }

    END {
      proven_consumers = proven_contract_consumers + proven_register_consumers
      optional_consumers = optional_contract_consumers + optional_register_consumers
      if (proof_bindings == 1 && proven_consumers == 2 && optional_consumers == 0) {
        source_shape = "proven_nested_return_type_consumed"
      } else if (proof_bindings == 0 && proven_consumers == 0 && optional_consumers == 2) {
        source_shape = "optional_nested_return_type_leaked"
      } else {
        source_shape = "ambiguous_nested_return_type_provenance"
      }

      print "source_shape=" source_shape
      print "proof_bindings=" (proof_bindings + 0)
      print "proven_contract_consumers=" (proven_contract_consumers + 0)
      print "proven_register_consumers=" (proven_register_consumers + 0)
      print "optional_contract_consumers=" (optional_contract_consumers + 0)
      print "optional_register_consumers=" (optional_register_consumers + 0)
    }
  ' "$SOURCE_FILE"
)"

printf '%s\n' "$report"
source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"

if [[ "$REQUIRE_PROVEN_RETURN_TYPE" == "1" && "$source_shape" != "proven_nested_return_type_consumed" ]]; then
  echo "FAIL: expected proven_nested_return_type_consumed, got $source_shape" >&2
  exit 9
fi

echo "PASS: nested-module return-type provenance source-shape status=$source_shape"
