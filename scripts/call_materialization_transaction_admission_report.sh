#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"

PREFERRED_SEAM="${PREFERRED_SEAM:-lower_function_if_needed.call_materialization_transaction}"
REQUIRE_PROMOTED="${REQUIRE_PROMOTED:-0}"
SAMPLES="${SAMPLES:-12}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/call_materialization_transaction_admission_report.sh
env:
  PREFERRED_SEAM=lower_function_if_needed.call_materialization_transaction
  REQUIRE_PROMOTED=0|1
  SAMPLES=12

Behavior-neutral source-shape gate for Slice 0k-AE. It selects the vertical
CallMaterializationTransaction seam and prevents generated-stage crash pursuit,
backend forwarders, requested-name forcing, target keepalive, NamedTuple/Tuple
normalization, or ambient-map predicate patches from counting as architecture
progress before a single HIR-owned transaction record exists.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

transaction_source_shape() {
  awk -v samples="$SAMPLES" '
    function keep_sample(kind, row) {
      if (sample_count[kind] < samples) {
        sample_count[kind]++
        sample[kind, sample_count[kind]] = row
      }
    }

    /private def lower_function_if_needed_impl\(name : String\)/ {
      in_method = 1
      next
    }

    in_method && /^    private def / {
      in_method = 0
    }

    in_method {
      code = $0
      sub(/[[:space:]]+#.*/, "", code)

      if (index(code, "CallMaterializationTransaction") > 0) {
        transaction_type++
        keep_sample("transaction_type", NR ":" $0)
      }
      if (index(code, "call_materialization_transaction") > 0) {
        transaction_helper++
        keep_sample("transaction_helper", NR ":" $0)
      }
      if (index(code, "MaterializationIdentityTransaction") > 0) {
        legacy_identity_tx++
        keep_sample("legacy_identity_tx", NR ":" $0)
      }
      if (index(code, "MaterializationSymbolBinding") > 0) {
        symbol_binding++
        keep_sample("symbol_binding", NR ":" $0)
      }
      if (index(code, "materialization_symbol_binding(") > 0) {
        symbol_binding_helper++
        keep_sample("symbol_binding_helper", NR ":" $0)
      }
      if (index(code, "materialized_name = materialization_symbol_binding_state_key(") > 0) {
        split_state_key++
        keep_sample("split_state_key", NR ":" $0)
      }
      if (index(code, "target_name = resolved_target_name") > 0) {
        split_target++
        keep_sample("split_target", NR ":" $0)
      }
      if (index(code, "has_untyped_regular_param = materialization_override_shadow_untyped_regular_param?(") > 0) {
        ambient_state_scope_consumer++
        keep_sample("ambient_state_scope_consumer", NR ":" $0)
      }
      if (index(code, "log_materialization_identity_ledger(") > 0) {
        legacy_ledger_call++
        keep_sample("legacy_ledger_call", NR ":" $0)
      }
      if (index(code, "with_isolated_type_param_map(merged_params)") > 0 ||
          index(code, "with_isolated_type_param_map(extra_type_params)") > 0) {
        direct_type_param_scope++
        keep_sample("direct_type_param_scope", NR ":" $0)
      }
      if (index(code, "lower_method(") > 0 ||
          index(code, "lower_def(") > 0 ||
          index(code, "lower_module_method(") > 0) {
        direct_body_lowering++
        keep_sample("direct_body_lowering", NR ":" $0)
      }
      if (index(code, "symbol_binding.") > 0) {
        symbol_binding_field_read++
        keep_sample("symbol_binding_field_read", NR ":" $0)
      }
      if (index(code, "transaction.") > 0) {
        transaction_field_read++
        keep_sample("transaction_field_read", NR ":" $0)
      }
    }

    END {
      legacy_edges = split_state_key + split_target + ambient_state_scope_consumer + legacy_ledger_call + direct_type_param_scope + direct_body_lowering + symbol_binding_field_read

      if (transaction_type > 0 && transaction_helper > 0 &&
          transaction_field_read > 0 && legacy_edges == 0) {
        source_shape = "already_promoted_shadow"
      } else if (transaction_type > 0 || transaction_helper > 0) {
        source_shape = "partial_transaction_authority"
      } else if (legacy_edges > 0) {
        source_shape = "legacy_split_transaction_edge"
      } else {
        source_shape = "missing_expected_edge"
      }

      print "source_shape=" source_shape
      print "transaction_type_count=" transaction_type + 0
      print "transaction_helper_count=" transaction_helper + 0
      print "legacy_identity_transaction_count=" legacy_identity_tx + 0
      print "symbol_binding_count=" symbol_binding + 0
      print "symbol_binding_helper_count=" symbol_binding_helper + 0
      print "split_state_key_count=" split_state_key + 0
      print "split_target_count=" split_target + 0
      print "ambient_state_scope_consumer_count=" ambient_state_scope_consumer + 0
      print "legacy_ledger_call_count=" legacy_ledger_call + 0
      print "direct_type_param_scope_count=" direct_type_param_scope + 0
      print "direct_body_lowering_count=" direct_body_lowering + 0
      print "symbol_binding_field_read_count=" symbol_binding_field_read + 0
      print "transaction_field_read_count=" transaction_field_read + 0

      kind_order = "transaction_type transaction_helper legacy_identity_tx symbol_binding symbol_binding_helper split_state_key split_target ambient_state_scope_consumer legacy_ledger_call direct_type_param_scope direct_body_lowering symbol_binding_field_read transaction_field_read"
      kind_total = split(kind_order, kinds, " ")
      for (kind_idx = 1; kind_idx <= kind_total; kind_idx++) {
        kind = kinds[kind_idx]
        print "sample_" kind "_count=" sample_count[kind] + 0
        for (idx = 1; idx <= sample_count[kind]; idx++) {
          print "sample_" kind "_" idx "=" sample[kind, idx]
        }
      }
    }
  ' "$SOURCE_FILE"
}

report="$(transaction_source_shape)"
source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"

selection_status="rejected"
case "$PREFERRED_SEAM:$source_shape" in
  lower_function_if_needed.call_materialization_transaction:legacy_split_transaction_edge)
    selection_status="eligible_transaction_spine_owner"
    ;;
  lower_function_if_needed.call_materialization_transaction:already_promoted_shadow)
    selection_status="already_promoted_shadow"
    ;;
  lower_function_if_needed.call_materialization_transaction:partial_transaction_authority)
    selection_status="rejected_partial_transaction_authority"
    ;;
  lower_function_if_needed.call_materialization_transaction:missing_expected_edge)
    selection_status="rejected_missing_source_edge"
    ;;
esac

echo "# CallMaterializationTransaction Admission Report"
echo "source: $SOURCE_FILE"
echo "preferred_seam: $PREFERRED_SEAM"
echo "preferred_source_shape: $source_shape"
echo "require_promoted: $REQUIRE_PROMOTED"
echo "note: source-shape gate only; no compiler behavior changes"
echo ""
echo "## Counts"
printf '%s\n' "$report" | awk -F= '
  $1 != "source_shape" && $1 !~ /^sample_/ {
    print
  }
'
echo ""
echo "## Candidate Selection"
echo "[CALL_MATERIALIZATION_TRANSACTION_ADMISSION] seam=lower_function_if_needed.call_materialization_transaction owner=CallMaterializationTransaction old_edge=split_requested_selected_target_body_call_state_abi owned_edge=single_transaction_spine source_shape=$source_shape selection_status=$selection_status next_action=source_shape_then_shadow_parity_helper"
echo ""
echo "## Samples"
printf '%s\n' "$report" | awk -F= '
  $1 ~ /^sample_/ {
    print
  }
'

if [[ "$selection_status" == "rejected_missing_source_edge" ]]; then
  echo "FAIL: preferred CallMaterializationTransaction seam source shape is missing" >&2
  exit 1
fi

if [[ "$selection_status" == "rejected_partial_transaction_authority" ]]; then
  echo "FAIL: partial CallMaterializationTransaction authority detected" >&2
  exit 1
fi

if [[ "$REQUIRE_PROMOTED" == "1" && "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: preferred CallMaterializationTransaction seam is not promoted yet" >&2
  exit 9
fi

if [[ "$selection_status" != "eligible_transaction_spine_owner" &&
      "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: no CallMaterializationTransaction seam selected" >&2
  exit 1
fi
