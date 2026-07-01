#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"

PREFERRED_SEAM="${PREFERRED_SEAM:-lower_function_if_needed.instance_symbol_consumers}"
REQUIRE_PROMOTED="${REQUIRE_PROMOTED:-0}"
SAMPLES="${SAMPLES:-10}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/call_materialization_transaction_consumer_selection_report.sh
env:
  PREFERRED_SEAM=lower_function_if_needed.instance_symbol_consumers
  REQUIRE_PROMOTED=0|1
  SAMPLES=10

Source-shape selection gate after Slice 0k-AF. It chooses the next
CallMaterializationTransaction consumer edge without changing compiler behavior:
the instance-method override, keepalive, and diagnostic materialization-symbol
consumers still read MaterializationSymbolBinding fields directly instead of a
CallMaterializationTransaction.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

consumer_source_shape() {
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

      if (index(code, "= call_materialization_transaction(") > 0) {
        transaction_constructor++
        keep_sample("transaction_constructor", NR ":" $0)
      }

      if (index(code, "instance_transaction.") > 0 ||
          index(code, "class_transaction.") > 0 ||
          index(code, "def_transaction.") > 0) {
        transaction_field_read++
        keep_sample("transaction_field_read", NR ":" $0)
      }

      if (index(code, "override = symbol_binding.override_symbol") > 0 ||
          index(code, "override_reason = symbol_binding.override_reason") > 0) {
        instance_override_binding++
        keep_sample("instance_override_binding", NR ":" $0)
      }

      if (index(code, "record_materialization_keepalive_candidate(") > 0) {
        in_keepalive_call = 1
        keepalive_window = 0
      }
      if (in_keepalive_call) {
        keepalive_window++
        if (index(code, "symbol_binding.") > 0) {
          keepalive_binding++
          keep_sample("keepalive_binding", NR ":" $0)
        }
        if (keepalive_window > 12) {
          in_keepalive_call = 0
        }
      }

      if (index(code, "ADAMAS_REGMAT_ASSERT") > 0) {
        in_regmat_assert = 1
        regmat_window = 0
      }
      if (in_regmat_assert) {
        regmat_window++
        if (index(code, "symbol_binding.") > 0) {
          regmat_binding++
          keep_sample("regmat_binding", NR ":" $0)
        }
        if (regmat_window > 18) {
          in_regmat_assert = 0
        }
      }

      if (index(code, "lower_method(") > 0 ||
          index(code, "lower_def(") > 0 ||
          index(code, "lower_module_method(") > 0) {
        direct_body_lowering++
        keep_sample("direct_body_lowering", NR ":" $0)
      }
    }

    END {
      selected_binding_consumers = instance_override_binding + keepalive_binding + regmat_binding

      if (transaction_constructor > 0 &&
          transaction_field_read > 0 &&
          selected_binding_consumers == 0) {
        source_shape = "already_promoted_shadow"
      } else if (transaction_constructor > 0 &&
                 selected_binding_consumers > 0 &&
                 transaction_field_read == 0) {
        source_shape = "legacy_instance_symbol_consumers"
      } else if (transaction_constructor > 0 &&
                 selected_binding_consumers > 0 &&
                 transaction_field_read > 0) {
        source_shape = "partial_transaction_consumer_authority"
      } else {
        source_shape = "missing_expected_edge"
      }

      print "source_shape=" source_shape
      print "transaction_constructor_count=" transaction_constructor + 0
      print "transaction_field_read_count=" transaction_field_read + 0
      print "instance_override_binding_count=" instance_override_binding + 0
      print "keepalive_binding_count=" keepalive_binding + 0
      print "regmat_binding_count=" regmat_binding + 0
      print "selected_binding_consumer_count=" selected_binding_consumers + 0
      print "direct_body_lowering_count=" direct_body_lowering + 0

      kind_order = "transaction_constructor transaction_field_read instance_override_binding keepalive_binding regmat_binding direct_body_lowering"
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

report="$(consumer_source_shape)"
source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"

selection_status="rejected"
case "$PREFERRED_SEAM:$source_shape" in
  lower_function_if_needed.instance_symbol_consumers:legacy_instance_symbol_consumers)
    selection_status="eligible_transaction_consumer_owner"
    ;;
  lower_function_if_needed.instance_symbol_consumers:already_promoted_shadow)
    selection_status="already_promoted_shadow"
    ;;
  lower_function_if_needed.instance_symbol_consumers:partial_transaction_consumer_authority)
    selection_status="rejected_partial_transaction_consumer_authority"
    ;;
  lower_function_if_needed.instance_symbol_consumers:missing_expected_edge)
    selection_status="rejected_missing_source_edge"
    ;;
esac

echo "# CallMaterializationTransaction Consumer Selection Report"
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
echo "[CALL_MATERIALIZATION_TRANSACTION_CONSUMER_SELECTION] seam=lower_function_if_needed.instance_symbol_consumers owner=CallMaterializationTransaction old_edge=instance_symbol_binding_direct_consumers owned_edge=transaction_symbol_consumers source_shape=$source_shape selection_status=$selection_status next_action=shadow_parity_transaction_consumer_helper"
echo ""
echo "## Samples"
printf '%s\n' "$report" | awk -F= '
  $1 ~ /^sample_/ {
    print
  }
'

if [[ "$selection_status" == "rejected_missing_source_edge" ]]; then
  echo "FAIL: preferred CallMaterializationTransaction consumer edge is missing" >&2
  exit 1
fi

if [[ "$selection_status" == "rejected_partial_transaction_consumer_authority" ]]; then
  echo "FAIL: partial CallMaterializationTransaction consumer authority detected" >&2
  exit 1
fi

if [[ "$REQUIRE_PROMOTED" == "1" && "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: preferred CallMaterializationTransaction consumer edge is not promoted yet" >&2
  exit 9
fi

if [[ "$selection_status" != "eligible_transaction_consumer_owner" &&
      "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: no CallMaterializationTransaction consumer edge selected" >&2
  exit 1
fi
