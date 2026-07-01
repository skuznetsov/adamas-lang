#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_transaction_edge_selection_report.sh [source.cr]

Build/use a generated-stage classifier log, aggregate transaction-bound
[MAT_EMIT] rows by their [MAT_TX] transaction metadata, and select the next
reached CallMaterializationTransaction emission edge.

Environment:
  LOG_FILE             Parse an existing classifier compile log instead of running the classifier.
  KEEP_TMP=1           Keep temporary classifier/wrapper directories.
  REQUIRE_SELECTED=1   Exit nonzero unless the selected edge is eligible.
  REQUIRE_POST_CONSUMER_STATE
                       Exit nonzero unless post_consumer_state matches this value.
  MAX_SELECTED_ROWS    Maximum rows accepted as root-sized (default: 8).
  REQUIRE_RESIDUAL_SELECTED=1
                       Exit nonzero unless the post-consumer exact-missing-body residual selects one root-sized class.
  MAX_RESIDUAL_ROWS    Maximum rows accepted for one residual class (default: 3).
  SAMPLES              Number of sample rows per section (default: 8).

Classifier passthrough environment when LOG_FILE is not set:
  STAGE1_COMPILER, GENERATED_S2, STAGE2_BUILD_TIMEOUT, STAGE2_BUILD_MEM_MB,
  SMOKE_TIMEOUT, SMOKE_MEM_MB, CLASSIFIER_SAMPLE_ROWS, CLASSIFIER_TAIL_LINES.

Selected edge:
  call_materialization.wrapper_or_call_remap.extern_missing_body

The selected edge is behavior-neutral evidence only. It does not add backend
forwarders, force requested names, keep target bodies alive, normalize
NamedTuple/Tuple rendering, change ambient-map policy, or alter BlockOwner.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

MAX_SELECTED_ROWS="${MAX_SELECTED_ROWS:-8}"
MAX_RESIDUAL_ROWS="${MAX_RESIDUAL_ROWS:-3}"
SAMPLES="${SAMPLES:-8}"
TMP_DIR=""
CLASSIFIER_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    [[ -n "$TMP_DIR" ]] && echo "kept_wrapper_tmp=$TMP_DIR"
    [[ -n "$CLASSIFIER_TMP" ]] && echo "kept_classifier_tmp=$CLASSIFIER_TMP"
  else
    [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
    [[ -n "$CLASSIFIER_TMP" ]] && rm -rf "$CLASSIFIER_TMP"
  fi
  return 0
}
trap cleanup EXIT

classifier_rc="skipped"
classifier_classification="log_file"
classifier_output=""

if [[ -n "${LOG_FILE:-}" ]]; then
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "FAIL: LOG_FILE does not exist: $LOG_FILE" >&2
    exit 2
  fi
else
  mkdir -p "$ROOT_DIR/tmp"
  TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-edge-selection.XXXXXX")"
  classifier_output="$TMP_DIR/classifier.out"

  set +e
  KEEP_TMP=1 \
    SAMPLE_ROWS="${CLASSIFIER_SAMPLE_ROWS:-1}" \
    TAIL_LINES="${CLASSIFIER_TAIL_LINES:-12}" \
    "$ROOT_DIR/scripts/generated_stage_transaction_spine_classifier.sh" "$@" >"$classifier_output" 2>&1
  classifier_rc=$?
  set -e

  LOG_FILE="$(awk -F= '$1 == "classifier_log" { print $2; exit }' "$classifier_output")"
  CLASSIFIER_TMP="$(awk -F= '$1 == "kept_tmp" { print $2; exit }' "$classifier_output")"
  classifier_classification="$(awk -F= '$1 == "classification" { print $2; exit }' "$classifier_output")"

  if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo "FAIL: classifier did not produce a parseable classifier_log" >&2
    echo "classifier_rc=$classifier_rc" >&2
    tail -120 "$classifier_output" >&2 || true
    exit 2
  fi
fi

echo "# Generated Stage Transaction Edge Selection Report"
echo "log_file=$LOG_FILE"
echo "classifier_rc=$classifier_rc"
echo "classifier_classification=$classifier_classification"
echo "max_selected_rows=$MAX_SELECTED_ROWS"
echo "max_residual_rows=$MAX_RESIDUAL_ROWS"
echo "samples=$SAMPLES"
echo "require_selected=${REQUIRE_SELECTED:-0}"
echo "require_residual_selected=${REQUIRE_RESIDUAL_SELECTED:-0}"
echo "require_post_consumer_state=${REQUIRE_POST_CONSUMER_STATE:-}"
echo "note: source-shape/reachability gate only; no compiler behavior changes"
echo ""

report="$(
  awk -v max_rows="$MAX_SELECTED_ROWS" -v max_residual_rows="$MAX_RESIDUAL_ROWS" -v samples="$SAMPLES" '
    function field(name,    i, p) {
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p > 0 && substr($i, 1, p - 1) == name) {
          return substr($i, p + 1)
        }
      }
      return ""
    }

    function keep_sample(kind, row) {
      if (sample_count[kind] < samples) {
        sample_count[kind]++
        sample[kind, sample_count[kind]] = row
      }
    }

    function emitted_owner_of(emitted,    owner) {
      owner = emitted
      sub(/\$H.*/, "", owner)
      return owner
    }

    function remember_residual_group(key, tx, emitted) {
      if (!(key in residual_group_seen)) {
        residual_group_seen[key] = 1
        residual_group_order[++residual_group_total] = key
        residual_group_phase[key] = phase[tx]
        residual_group_branch[key] = branch[tx]
        residual_group_owner[key] = selected_owner[tx]
        residual_group_emitted_owner[key] = emitted_owner_of(emitted)
        residual_group_required_contract[key] = required_contract[tx]
        residual_group_symbol_relation[key] = symbol_relation[tx]
        residual_group_identity_status[key] = identity_status[tx]
      }
    }

    /^\[MAT_TX\]/ {
      mat_tx_rows++
      tx = field("tx")
      if (tx == "") {
        malformed_tx++
        keep_sample("malformed_tx", $0)
        next
      }

      tx_seen[tx] = 1
      phase[tx] = field("phase")
      requested[tx] = field("requested")
      target[tx] = field("target")
      body_symbol[tx] = field("body_symbol")
      call_symbol_hint[tx] = field("call_symbol_hint")
      identity_status[tx] = field("identity_status")
      symbol_relation[tx] = field("symbol_relation")
      required_contract[tx] = field("required_contract")
      override_reason[tx] = field("override_reason")
      branch[tx] = field("branch")
      selected_owner[tx] = field("selected_owner")
      state_scope[tx] = field("state_scope")
      map_source[tx] = field("map_source")
      materialization_action[tx] = field("materialization_action")
      wrapper_forwarder_contract[tx] = field("wrapper_forwarder_contract")
      rejection_reason[tx] = field("rejection_reason")
    }

    /^\[MAT_EMIT\]/ {
      mat_emit_rows++
      tx = field("tx")
      kind = field("kind")
      emitted = field("emitted")
      body_present = field("body_present")
      emit_required_contract = field("required_contract")
      emit_body_symbol = field("body_symbol")
      emit_call_symbol_hint = field("call_symbol_hint")
      emit_symbol_relation = field("symbol_relation")
      emit_identity_status = field("identity_status")

      if (tx == "" || kind == "" || emitted == "" || body_present == "") {
        malformed_emit++
        keep_sample("malformed_emit", $0)
        next
      }

      if (tx == "none") {
        non_transaction_emit_rows++
        keep_sample("non_transaction_emit", $0)
        next
      }

      transaction_bound_emit_rows++
      transaction_emit_seen[tx] = 1

      if (!(tx in tx_seen)) {
        unjoined_emit_rows++
        keep_sample("unjoined_emit", $0)
      }

      if (body_present == "0") {
        missing_body_emit_rows++
        keep_sample("missing_body_emit", $0)
      }

      if (emit_required_contract != "" && emit_required_contract != "none") {
        contract_consumer_rows++
        if (emit_required_contract != required_contract[tx] ||
            emit_body_symbol != body_symbol[tx] ||
            emit_call_symbol_hint != call_symbol_hint[tx] ||
            emit_symbol_relation != symbol_relation[tx] ||
            emit_identity_status != identity_status[tx]) {
          contract_mismatch_rows++
          keep_sample("contract_mismatch", $0)
        }
        if (emit_required_contract == "wrapper_or_call_remap" &&
            emit_symbol_relation == "body_eq_target_call_eq_requested" &&
            emit_identity_status == "rejected_mismatch" &&
            emit_body_symbol == body_symbol[tx] &&
            emit_call_symbol_hint == call_symbol_hint[tx]) {
          candidate_contract_consumer_rows++
          keep_sample("contract_consumer", $0)
        }
      }

      if (required_contract[tx] == "wrapper_or_call_remap" &&
          symbol_relation[tx] == "body_eq_target_call_eq_requested" &&
          identity_status[tx] == "rejected_mismatch" &&
          kind == "extern" &&
          body_present == "0") {
        selected_rows++
        selected_tx_seen[tx] = 1
        selected_owner_count[selected_owner[tx]]++
        selected_branch_count[branch[tx]]++
        selected_sample = "tx=" tx " requested=" requested[tx] " target=" target[tx] " body=" body_symbol[tx] " call=" call_symbol_hint[tx] " emitted=" emitted " owner=" selected_owner[tx] " branch=" branch[tx]
        keep_sample("selected_edge", selected_sample)
      } else if (required_contract[tx] == "wrapper_or_call_remap") {
        adjacent_contract_rows++
        keep_sample("adjacent_contract", $0)
      } else if (body_present == "0") {
        other_missing_body_rows++
        keep_sample("other_missing_body", $0)
        if (required_contract[tx] == "none" &&
            symbol_relation[tx] == "all_equal" &&
            identity_status[tx] == "exact" &&
            kind == "extern") {
          residual_exact_missing_rows++
          residual_key = phase[tx] "|" branch[tx] "|" emitted_owner_of(emitted) "|" required_contract[tx] "|" symbol_relation[tx] "|" identity_status[tx]
          residual_group_count[residual_key]++
          remember_residual_group(residual_key, tx, emitted)
          residual_sample = "group=" residual_key " tx=" tx " requested=" requested[tx] " target=" target[tx] " body=" body_symbol[tx] " call=" call_symbol_hint[tx] " emitted=" emitted " owner=" selected_owner[tx] " branch=" branch[tx]
          keep_sample("residual_exact_missing", residual_sample)
        }
      }
    }

    END {
      for (tx in transaction_emit_seen) {
        distinct_transaction_emit_txs++
      }
      for (tx in selected_tx_seen) {
        selected_distinct_txs++
      }
      for (owner in selected_owner_count) {
        selected_owner_kinds++
      }
      for (branch_name in selected_branch_count) {
        selected_branch_kinds++
      }
      for (i = 1; i <= residual_group_total; i++) {
        key = residual_group_order[i]
        if ((residual_group_count[key] + 0) <= max_residual_rows) {
          residual_root_sized_groups++
          residual_candidate_key = key
          residual_candidate_rows = residual_group_count[key] + 0
        }
      }

      if (malformed_tx != 0 || malformed_emit != 0 || unjoined_emit_rows != 0 ||
          contract_mismatch_rows != 0) {
        source_shape = "malformed_ledger"
        selection_status = "rejected_malformed_ledger"
        post_consumer_state = "selected_refuted_or_stale"
      } else if (selected_rows == 0 && candidate_contract_consumer_rows > 0) {
        source_shape = "selected_consumed_by_contract_consumer"
        selection_status = "eligible_contract_consumer_state"
        post_consumer_state = "selected_consumed_by_contract_consumer"
      } else if (selected_rows == 0) {
        source_shape = "missing_selected_edge"
        selection_status = "rejected_missing_selected_edge"
        post_consumer_state = "selected_refuted_or_stale"
      } else if (selected_rows > max_rows) {
        source_shape = "selected_edge_too_wide"
        selection_status = "rejected_selected_edge_too_wide"
        post_consumer_state = "selected_refuted_or_stale"
      } else {
        source_shape = "eligible_reached_edge"
        selection_status = "eligible_reached_transaction_emission_edge"
        post_consumer_state = "selected_not_consumed"
      }

      if (malformed_tx != 0 || malformed_emit != 0 || unjoined_emit_rows != 0 ||
          contract_mismatch_rows != 0) {
        residual_selection_status = "rejected_malformed_ledger"
      } else if ((residual_exact_missing_rows + 0) == 0) {
        residual_selection_status = "no_exact_missing_body_residual"
      } else if ((residual_root_sized_groups + 0) == 0) {
        residual_selection_status = "rejected_exact_missing_body_too_wide"
      } else if ((residual_root_sized_groups + 0) > 1) {
        residual_selection_status = "rejected_exact_missing_body_ambiguous"
      } else {
        residual_selection_status = "eligible_exact_missing_body_edge"
        residual_selected_key = residual_candidate_key
        residual_selected_rows = residual_candidate_rows + 0
      }

      print "## Counts"
      print "mat_tx_rows=" mat_tx_rows + 0
      print "mat_emit_rows=" mat_emit_rows + 0
      print "transaction_bound_emit_rows=" transaction_bound_emit_rows + 0
      print "non_transaction_emit_rows=" non_transaction_emit_rows + 0
      print "distinct_transaction_bound_txs=" distinct_transaction_emit_txs + 0
      print "missing_body_emit_rows=" missing_body_emit_rows + 0
      print "candidate_selected_rows=" selected_rows + 0
      print "candidate_selected_distinct_txs=" selected_distinct_txs + 0
      print "candidate_selected_owner_kinds=" selected_owner_kinds + 0
      print "candidate_selected_branch_kinds=" selected_branch_kinds + 0
      print "contract_consumer_rows=" contract_consumer_rows + 0
      print "candidate_contract_consumer_rows=" candidate_contract_consumer_rows + 0
      print "contract_mismatch_rows=" contract_mismatch_rows + 0
      print "adjacent_wrapper_contract_rows=" adjacent_contract_rows + 0
      print "other_missing_body_rows=" other_missing_body_rows + 0
      print "residual_exact_missing_body_rows=" residual_exact_missing_rows + 0
      print "residual_exact_missing_body_groups=" residual_group_total + 0
      print "residual_exact_missing_body_root_sized_groups=" residual_root_sized_groups + 0
      print "residual_exact_missing_body_selected_rows=" residual_selected_rows + 0
      print "malformed_tx_rows=" malformed_tx + 0
      print "malformed_emit_rows=" malformed_emit + 0
      print "unjoined_emit_rows=" unjoined_emit_rows + 0

      print ""
      print "## Candidate Selection"
      print "selected_edge=call_materialization.wrapper_or_call_remap.extern_missing_body"
      print "candidate_required_contract=wrapper_or_call_remap"
      print "candidate_symbol_relation=body_eq_target_call_eq_requested"
      print "candidate_identity_status=rejected_mismatch"
      print "candidate_emit_kind=extern"
      print "candidate_emit_body_present=0"
      print "source_shape=" source_shape
      print "selection_status=" selection_status
      print "post_consumer_state=" post_consumer_state
      print "[GENERATED_STAGE_TRANSACTION_EDGE_SELECTION] edge=call_materialization.wrapper_or_call_remap.extern_missing_body owner=CallMaterializationTransaction old_edge=backend_extern_emission_from_call_symbol_hint_without_body owned_edge=transaction_required_contract_body_symbol_call_symbol_hint source_shape=" source_shape " selection_status=" selection_status " post_consumer_state=" post_consumer_state " next_action=refresh_consumer_state_gate_then_shadow_parity_consumer"

      print ""
      print "## Residual Exact Missing-Body Selection"
      print "residual_edge=call_materialization.exact_contract.extern_missing_body"
      print "residual_required_contract=none"
      print "residual_symbol_relation=all_equal"
      print "residual_identity_status=exact"
      print "residual_emit_kind=extern"
      print "residual_emit_body_present=0"
      print "residual_selection_status=" residual_selection_status
      print "residual_selected_key=" residual_selected_key
      print "[GENERATED_STAGE_RESIDUAL_EDGE_SELECTION] edge=call_materialization.exact_contract.extern_missing_body owner=CallMaterializationTransaction old_edge=backend_extern_emission_from_exact_call_symbol_without_body owned_edge=transaction_body_symbol_call_symbol_hint_exact_identity source_shape=" residual_selection_status " selected_key=" residual_selected_key " selected_rows=" (residual_selected_rows + 0) " next_action=stop_if_broad_or_ambiguous_else_select_consumer_migration"

      print ""
      print "## Residual Exact Missing-Body Groups"
      if ((residual_group_total + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= residual_group_total; i++) {
          key = residual_group_order[i]
          print "group=" key " rows=" (residual_group_count[key] + 0) " root_sized=" (((residual_group_count[key] + 0) <= max_residual_rows) ? 1 : 0) " phase=" residual_group_phase[key] " branch=" residual_group_branch[key] " owner=" residual_group_owner[key] " emitted_owner=" residual_group_emitted_owner[key]
        }
      }

      print ""
      print "## Selected Edge Samples"
      if ((sample_count["selected_edge"] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count["selected_edge"]; i++) {
          print sample["selected_edge", i]
        }
      }

      print ""
      print "## Contract Consumer Samples"
      if ((sample_count["contract_consumer"] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count["contract_consumer"]; i++) {
          print sample["contract_consumer", i]
        }
      }

      print ""
      print "## Adjacent Contract Samples"
      if ((sample_count["adjacent_contract"] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count["adjacent_contract"]; i++) {
          print sample["adjacent_contract", i]
        }
      }

      print ""
      print "## Other Missing-Body Samples"
      if ((sample_count["other_missing_body"] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count["other_missing_body"]; i++) {
          print sample["other_missing_body", i]
        }
      }

      print ""
      print "## Residual Exact Missing-Body Samples"
      if ((sample_count["residual_exact_missing"] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count["residual_exact_missing"]; i++) {
          print sample["residual_exact_missing", i]
        }
      }

      print ""
      print "## Malformed Samples"
      if ((sample_count["malformed_tx"] + 0) == 0 &&
          (sample_count["malformed_emit"] + 0) == 0 &&
          (sample_count["unjoined_emit"] + 0) == 0 &&
          (sample_count["contract_mismatch"] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count["malformed_tx"]; i++) print sample["malformed_tx", i]
        for (i = 1; i <= sample_count["malformed_emit"]; i++) print sample["malformed_emit", i]
        for (i = 1; i <= sample_count["unjoined_emit"]; i++) print sample["unjoined_emit", i]
        for (i = 1; i <= sample_count["contract_mismatch"]; i++) print sample["contract_mismatch", i]
      }
    }
  ' "$LOG_FILE"
)"

printf '%s\n' "$report"

selection_status="$(awk -F= '$1 == "selection_status" { value = $2 } END { print value }' <<<"$report")"
post_consumer_state="$(awk -F= '$1 == "post_consumer_state" { value = $2 } END { print value }' <<<"$report")"
residual_selection_status="$(awk -F= '$1 == "residual_selection_status" { value = $2 } END { print value }' <<<"$report")"

if [[ "${REQUIRE_SELECTED:-0}" == "1" &&
      "$selection_status" != "eligible_reached_transaction_emission_edge" ]]; then
  echo "FAIL: no eligible reached transaction/emission edge selected" >&2
  exit 9
fi

if [[ -n "${REQUIRE_POST_CONSUMER_STATE:-}" &&
      "$post_consumer_state" != "$REQUIRE_POST_CONSUMER_STATE" ]]; then
  echo "FAIL: post_consumer_state=$post_consumer_state expected=$REQUIRE_POST_CONSUMER_STATE" >&2
  exit 9
fi

if [[ "${REQUIRE_RESIDUAL_SELECTED:-0}" == "1" &&
      "$residual_selection_status" != "eligible_exact_missing_body_edge" ]]; then
  echo "FAIL: residual_selection_status=$residual_selection_status expected=eligible_exact_missing_body_edge" >&2
  exit 9
fi

if [[ "$selection_status" == "rejected_malformed_ledger" ]]; then
  echo "FAIL: malformed transaction/emission ledger" >&2
  exit 1
fi

if [[ "$selection_status" != "eligible_reached_transaction_emission_edge" &&
      "$selection_status" != "eligible_contract_consumer_state" &&
      "$selection_status" != "rejected_missing_selected_edge" &&
      "$selection_status" != "rejected_selected_edge_too_wide" ]]; then
  echo "FAIL: unknown selection status: $selection_status" >&2
  exit 1
fi

if [[ "$residual_selection_status" != "eligible_exact_missing_body_edge" &&
      "$residual_selection_status" != "no_exact_missing_body_residual" &&
      "$residual_selection_status" != "rejected_exact_missing_body_too_wide" &&
      "$residual_selection_status" != "rejected_exact_missing_body_ambiguous" &&
      "$residual_selection_status" != "rejected_malformed_ledger" ]]; then
  echo "FAIL: unknown residual selection status: $residual_selection_status" >&2
  exit 1
fi

exit 0
