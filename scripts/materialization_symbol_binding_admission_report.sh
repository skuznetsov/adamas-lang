#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"

PREFERRED_SEAM="${PREFERRED_SEAM:-lower_function_if_needed.symbol_binding}"
REQUIRE_PROMOTED="${REQUIRE_PROMOTED:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/materialization_symbol_binding_admission_report.sh
env:
  PREFERRED_SEAM=lower_function_if_needed.symbol_binding
  REQUIRE_PROMOTED=0|1

Behavior-neutral source-shape gate for the MaterializationIdentity /
MaterializationRegistry row. It selects the lower_function_if_needed symbol
binding seam and prevents a record-only refactor from counting as architecture
progress.
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

source_shape_for_symbol_binding() {
  awk '
    /private def lower_function_if_needed_impl\(name : String\)/ {
      in_method = 1
      next
    }
    in_method && /private def / {
      in_method = 0
    }
    in_method {
      if (index($0, "MaterializationSymbolBinding") > 0) {
        binding_type = 1
      }
      if (index($0, "materialization_symbol_binding") > 0) {
        helper_call = 1
      }
      if (index($0, "materialized_name = if materialize_requested_instance_wrapper") > 0) {
        old_materialized_branch = 1
      }
      if (index($0, "override = if materialize_requested_instance_wrapper") > 0) {
        old_override_branch = 1
      }
      if (index($0, "record_materialization_keepalive_candidate(name, target_name, override || target_name)") > 0) {
        direct_keepalive = 1
      }
      if (index($0, "record_materialization_keepalive_candidate(") > 0) {
        in_keepalive_call = 1
        keepalive_window = 0
      }
      if (in_keepalive_call) {
        keepalive_window++
        if (index($0, "symbol_binding.") > 0 ||
            index($0, "binding.") > 0) {
          binding_keepalive = 1
        }
        if (keepalive_window > 12) {
          in_keepalive_call = 0
        }
      }
      if (index($0, "log_materialization_identity_ledger(") > 0) {
        in_ledger_call = 1
        ledger_window = 0
      }
      if (in_ledger_call) {
        ledger_window++
        if (index($0, "materialized_name,") > 0 ||
            index($0, "override || target_name,") > 0) {
          direct_ledger_symbols = 1
        }
        if (index($0, "symbol_binding.") > 0 ||
            index($0, "binding.") > 0) {
          binding_ledger_symbols = 1
        }
        if (ledger_window > 24) {
          in_ledger_call = 0
        }
      }
      if (index($0, "call_materialization_transaction(") > 0) {
        in_transaction_call = 1
        transaction_window = 0
      }
      if (in_transaction_call) {
        transaction_window++
        if (index($0, "symbol_binding,") > 0 ||
            index($0, "class_symbol_binding,") > 0 ||
            index($0, "def_symbol_binding,") > 0) {
          binding_transaction_symbols = 1
        }
        if (transaction_window > 16) {
          in_transaction_call = 0
        }
      }
    }
    END {
      if (binding_type && helper_call &&
          !old_materialized_branch && !old_override_branch &&
          !direct_keepalive && !direct_ledger_symbols &&
          (binding_keepalive || binding_transaction_symbols) &&
          (binding_ledger_symbols || binding_transaction_symbols)) {
        print "already_promoted_shadow"
      } else if (old_materialized_branch && old_override_branch && direct_keepalive && direct_ledger_symbols && !helper_call) {
        print "legacy_split_edge"
      } else if (binding_type || helper_call) {
        print "partial_binding_authority"
      } else {
        print "missing_expected_edge"
      }
    }
  ' "$SOURCE_FILE"
}

source_shape="$(source_shape_for_symbol_binding)"
binding_type_count="$(count_literal "MaterializationSymbolBinding")"
binding_helper_count="$(count_literal "materialization_symbol_binding")"
old_materialized_count="$(count_literal "materialized_name = if materialize_requested_instance_wrapper")"
old_override_count="$(count_literal "override = if materialize_requested_instance_wrapper")"
direct_keepalive_count="$(count_literal "record_materialization_keepalive_candidate(name, target_name, override || target_name)")"
direct_ledger_materialized_count="$(
  awk '
    /private def lower_function_if_needed_impl\(name : String\)/ { in_method = 1; next }
    in_method && /private def / { in_method = 0 }
    in_method {
      if (index($0, "log_materialization_identity_ledger(") > 0) {
        in_ledger_call = 1
        ledger_window = 0
      }
      if (in_ledger_call) {
        ledger_window++
        if (index($0, "materialized_name,") > 0) {
          count++
        }
        if (ledger_window > 24) {
          in_ledger_call = 0
        }
      }
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
)"
direct_ledger_override_count="$(
  awk '
    /private def lower_function_if_needed_impl\(name : String\)/ { in_method = 1; next }
    in_method && /private def / { in_method = 0 }
    in_method {
      if (index($0, "log_materialization_identity_ledger(") > 0) {
        in_ledger_call = 1
        ledger_window = 0
      }
      if (in_ledger_call) {
        ledger_window++
        if (index($0, "override || target_name,") > 0) {
          count++
        }
        if (ledger_window > 24) {
          in_ledger_call = 0
        }
      }
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
)"
binding_keepalive_count="$(
  awk '
    /record_materialization_keepalive_candidate\(/ {
      in_keepalive_call = 1
      keepalive_window = 0
    }
    in_keepalive_call {
      keepalive_window++
      if (index($0, "symbol_binding.") > 0 ||
          index($0, "binding.") > 0) {
        count++
      }
      if (keepalive_window > 12) {
        in_keepalive_call = 0
      }
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
)"
binding_ledger_count="$(
  awk '
    /log_materialization_identity_ledger\(/ {
      in_ledger_call = 1
      ledger_window = 0
    }
    in_ledger_call {
      ledger_window++
      if (index($0, "symbol_binding.") > 0 ||
          index($0, "binding.") > 0) {
        count++
      }
      if (ledger_window > 24) {
        in_ledger_call = 0
      }
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
)"
binding_transaction_count="$(
  awk '
    /call_materialization_transaction\(/ {
      in_transaction_call = 1
      transaction_window = 0
    }
    in_transaction_call {
      transaction_window++
      if (index($0, "symbol_binding,") > 0 ||
          index($0, "class_symbol_binding,") > 0 ||
          index($0, "def_symbol_binding,") > 0) {
        count++
      }
      if (transaction_window > 16) {
        in_transaction_call = 0
      }
    }
    END { print count + 0 }
  ' "$SOURCE_FILE"
)"

selection_status="rejected"
case "$PREFERRED_SEAM:$source_shape" in
  lower_function_if_needed.symbol_binding:legacy_split_edge)
    selection_status="eligible_symbol_binding_owner"
    ;;
  lower_function_if_needed.symbol_binding:already_promoted_shadow)
    selection_status="already_promoted_shadow"
    ;;
  lower_function_if_needed.symbol_binding:partial_binding_authority)
    selection_status="rejected_partial_binding_authority"
    ;;
  lower_function_if_needed.symbol_binding:missing_expected_edge)
    selection_status="rejected_missing_source_edge"
    ;;
esac

echo "# Materialization Symbol Binding Admission Report"
echo "source: $SOURCE_FILE"
echo "preferred_seam: $PREFERRED_SEAM"
echo "preferred_source_shape: $source_shape"
echo "require_promoted: $REQUIRE_PROMOTED"
echo "note: source-shape gate only; no compiler behavior changes"
echo ""
echo "## Counts"
echo "binding_type_count=$binding_type_count"
echo "binding_helper_count=$binding_helper_count"
echo "old_materialized_branch_count=$old_materialized_count"
echo "old_override_branch_count=$old_override_count"
echo "direct_keepalive_count=$direct_keepalive_count"
echo "direct_ledger_materialized_count=$direct_ledger_materialized_count"
echo "direct_ledger_override_count=$direct_ledger_override_count"
echo "binding_keepalive_count=$binding_keepalive_count"
echo "binding_ledger_count=$binding_ledger_count"
echo "binding_transaction_count=$binding_transaction_count"
echo ""
echo "## Candidate Selection"
echo "[MATERIALIZATION_SYMBOL_BINDING_ADMISSION] seam=lower_function_if_needed.symbol_binding owner=MaterializationIdentity/MaterializationRegistry old_edge=split_inline_symbol_binding owned_edge=MaterializationSymbolBinding source_shape=$source_shape selection_status=$selection_status next_action=shadow_parity_helper"

if [[ "$selection_status" == "rejected_missing_source_edge" ]]; then
  echo "FAIL: preferred MaterializationSymbolBinding seam source shape is missing" >&2
  exit 1
fi

if [[ "$selection_status" == "rejected_partial_binding_authority" ]]; then
  echo "FAIL: partial MaterializationSymbolBinding authority detected" >&2
  exit 1
fi

if [[ "$REQUIRE_PROMOTED" == "1" && "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: preferred MaterializationSymbolBinding seam is not promoted yet" >&2
  exit 9
fi

if [[ "$selection_status" != "eligible_symbol_binding_owner" &&
      "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: no MaterializationSymbolBinding seam selected" >&2
  exit 1
fi
