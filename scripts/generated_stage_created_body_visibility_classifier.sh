#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_created_body_visibility_classifier.sh [source.cr]

Build/use a generated-stage materialization transaction log and split the
created_body_backend_missing residual by the next self-applying visibility
boundary. This classifier consumes only [MAT_TX] and [MAT_EMIT] ledger facts.

Environment:
  LOG_FILE               Parse an existing classifier compile log.
  KEEP_TMP=1             Keep temporary classifier directories.
  MAX_CLASS_ROWS         Maximum rows accepted as one root-sized class (default: 3).
  SAMPLES                Sample rows per section (default: 8).
  REQUIRE_CLASSIFIED=1   Exit nonzero if residual rows are unclassified.
  REQUIRE_ROOT_SIZED=1   Exit nonzero unless exactly one root-sized class is selected.

Classifier passthrough environment when LOG_FILE is not set:
  STAGE1_COMPILER, GENERATED_S2, STAGE2_BUILD_TIMEOUT, STAGE2_BUILD_MEM_MB,
  SMOKE_TIMEOUT, SMOKE_MEM_MB, SAMPLE_ROWS, TAIL_LINES.

This is a read-only/source-shape classifier. It does not add backend rescue,
forwarders, requested-name forcing, per-method patches, NamedTuple/Tuple
normalization, ambient-map policy changes, or BlockOwner changes.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

MAX_CLASS_ROWS="${MAX_CLASS_ROWS:-3}"
SAMPLES="${SAMPLES:-8}"
TMP_DIR=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    [[ -n "$TMP_DIR" ]] && echo "kept_tmp=$TMP_DIR"
  else
    [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
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
  TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/created-body-visibility.XXXXXX")"
  classifier_output="$TMP_DIR/classifier.out"

  set +e
  KEEP_TMP=1 \
    "$ROOT_DIR/scripts/generated_stage_transaction_spine_classifier.sh" "$@" >"$classifier_output" 2>&1
  classifier_rc=$?
  set -e

  LOG_FILE="$(awk -F= '$1 == "classifier_log" { print $2; exit }' "$classifier_output")"
  classifier_tmp="$(awk -F= '$1 == "kept_tmp" { print $2; exit }' "$classifier_output")"
  classifier_classification="$(awk -F= '$1 == "classification" { print $2; exit }' "$classifier_output")"

  if [[ -n "$classifier_tmp" && -d "$classifier_tmp" ]]; then
    if [[ "${KEEP_TMP:-0}" == "1" ]]; then
      echo "kept_classifier_tmp=$classifier_tmp"
    else
      cp "$LOG_FILE" "$TMP_DIR/classifier_compile.log"
      rm -rf "$classifier_tmp"
      LOG_FILE="$TMP_DIR/classifier_compile.log"
    fi
  fi

  if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo "FAIL: classifier did not produce a parseable classifier_log" >&2
    echo "classifier_rc=$classifier_rc" >&2
    tail -120 "$classifier_output" >&2 || true
    exit 2
  fi
fi

echo "# Generated Stage Created-Body Visibility Classifier"
echo "log_file=$LOG_FILE"
echo "classifier_rc=$classifier_rc"
echo "classifier_classification=$classifier_classification"
echo "max_class_rows=$MAX_CLASS_ROWS"
echo "samples=$SAMPLES"
echo "require_classified=${REQUIRE_CLASSIFIED:-0}"
echo "require_root_sized=${REQUIRE_ROOT_SIZED:-0}"
echo "note: source-shape/reachability gate only; no compiler behavior changes"
echo ""

report="$(
  awk -v max_class_rows="$MAX_CLASS_ROWS" -v samples="$SAMPLES" '
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

    function missing_required_fields(tx,    miss) {
      miss = ""
      if (body_function_present[tx] == "") miss = miss "body_function_present,"
      if (body_has_body[tx] == "") miss = miss "body_has_body,"
      if (body_state[tx] == "") miss = miss "body_state,"
      return miss
    }

    function missing_emit_fields(lookup, module, plan, emitted, undefined,    miss) {
      miss = ""
      if (lookup == "") miss = miss "lookup_present,"
      if (module == "") miss = miss "module_present,"
      if (plan == "") miss = miss "plan_present,"
      if (emitted == "") miss = miss "emitted_present,"
      if (undefined == "") miss = miss "undefined_present,"
      return miss
    }

    function visibility_cause(tx, lookup, module, plan, emitted, undefined,    miss) {
      miss = missing_required_fields(tx) missing_emit_fields(lookup, module, plan, emitted, undefined)
      if (miss != "") return "missing_visibility_fields"
      if (body_function_present[tx] != "1" && body_state[tx] == "in_progress") return "state_in_progress_without_hir_function"
      if (body_function_present[tx] != "1") return "hir_function_absent_after_created_body"
      if (body_has_body[tx] != "1") return "hir_body_absent_after_created_body"
      if (module != "1") return "mir_function_missing_after_hir_body"
      if (plan != "1") return "emission_plan_pruned_after_mir"
      if (lookup != "1") return "backend_lookup_miss_despite_mir"
      if (emitted != "1") return "planned_but_not_emitted_at_call_site"
      if (undefined == "1") return "undefined_even_with_visible_body"
      return "unclassified_visibility_gap"
    }

    function remember_group(key, cause, tx, emitted) {
      if (!(key in group_seen)) {
        group_seen[key] = 1
        group_order[++group_total] = key
        group_cause[key] = cause
        group_phase[key] = phase[tx]
        group_branch[key] = branch[tx]
        group_owner[key] = selected_owner[tx]
        group_body_state[key] = body_state[tx]
        group_emitted_owner[key] = emitted_owner_of(emitted)
      }
    }

    /^\[MAT_TX\]/ {
      mat_tx_rows++
      tx = field("tx")
      if (tx == "") {
        malformed_tx++
        keep_sample("malformed", $0)
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
      branch[tx] = field("branch")
      selected_owner[tx] = field("selected_owner")
      materialization_action[tx] = field("materialization_action")
      body_function_present[tx] = field("body_function_present")
      body_has_body[tx] = field("body_has_body")
      body_state[tx] = field("body_state")
    }

    /^\[MAT_EMIT\]/ {
      mat_emit_rows++
      tx = field("tx")
      kind = field("kind")
      emitted = field("emitted")
      body_present = field("body_present")
      lookup = field("lookup_present")
      module = field("module_present")
      plan = field("plan_present")
      emitted_flag = field("emitted_present")
      undefined = field("undefined_present")
      emit_required_contract = field("required_contract")
      emit_symbol_relation = field("symbol_relation")
      emit_identity_status = field("identity_status")

      if (tx == "" || kind == "" || emitted == "" || body_present == "") {
        malformed_emit++
        keep_sample("malformed", $0)
        next
      }
      if (tx == "none") {
        non_transaction_emit_rows++
        next
      }
      transaction_bound_emit_rows++
      if (!(tx in tx_seen)) {
        unjoined_emit_rows++
        keep_sample("malformed", $0)
      }

      if (body_present == "0") missing_body_emit_rows++

      if (body_present == "0" &&
          kind == "extern" &&
          required_contract[tx] == "none" &&
          symbol_relation[tx] == "all_equal" &&
          identity_status[tx] == "exact" &&
          materialization_action[tx] == "created_body" &&
          emit_required_contract == required_contract[tx] &&
          emit_symbol_relation == symbol_relation[tx] &&
          emit_identity_status == identity_status[tx]) {
        residual_rows++
        cause = visibility_cause(tx, lookup, module, plan, emitted_flag, undefined)
        cause_count[cause]++
        if (cause == "missing_visibility_fields") missing_visibility_field_rows++
        group_key = cause "|" phase[tx] "|" branch[tx] "|" body_state[tx] "|" emitted_owner_of(emitted)
        group_count[group_key]++
        remember_group(group_key, cause, tx, emitted)
        residual_sample = "cause=" cause " tx=" tx " requested=" requested[tx] " body=" body_symbol[tx] " emitted=" emitted " action=" materialization_action[tx] " hir_func=" body_function_present[tx] " hir_body=" body_has_body[tx] " hir_state=" body_state[tx] " lookup=" lookup " module=" module " plan=" plan " emitted_present=" emitted_flag " undefined=" undefined " owner=" selected_owner[tx] " branch=" branch[tx]
        keep_sample(cause, residual_sample)
        keep_sample("residual", residual_sample)
      }
    }

    END {
      for (cause in cause_count) {
        cause_kinds++
        selected_cause = cause
        selected_rows = cause_count[cause] + 0
        if ((cause_count[cause] + 0) <= max_class_rows) {
          root_sized_cause_count++
        }
      }
      for (i = 1; i <= group_total; i++) {
        key = group_order[i]
        if ((group_count[key] + 0) <= max_class_rows) {
          root_sized_groups++
        }
      }

      if (malformed_tx != 0 || malformed_emit != 0 || unjoined_emit_rows != 0) {
        classification = "rejected_malformed_ledger"
      } else if ((residual_rows + 0) == 0) {
        classification = "no_created_body_missing_visibility_residual"
      } else if (cause_kinds == 0) {
        classification = "rejected_unclassified_residual"
      } else if (missing_visibility_field_rows != 0) {
        classification = "rejected_missing_visibility_fields"
      } else if (cause_kinds > 1) {
        classification = "rejected_mixed_visibility_causes"
      } else if (selected_rows > max_class_rows || selected_rows == 0) {
        classification = "rejected_visibility_class_too_wide"
      } else {
        classification = "eligible_visibility_edge"
      }

      print "## Counts"
      print "mat_tx_rows=" mat_tx_rows + 0
      print "mat_emit_rows=" mat_emit_rows + 0
      print "transaction_bound_emit_rows=" transaction_bound_emit_rows + 0
      print "non_transaction_emit_rows=" non_transaction_emit_rows + 0
      print "missing_body_emit_rows=" missing_body_emit_rows + 0
      print "created_body_missing_visibility_rows=" residual_rows + 0
      print "visibility_cause_kinds=" cause_kinds + 0
      print "visibility_groups=" group_total + 0
      print "visibility_root_sized_groups=" root_sized_groups + 0
      print "missing_visibility_field_rows=" missing_visibility_field_rows + 0
      print "malformed_tx_rows=" malformed_tx + 0
      print "malformed_emit_rows=" malformed_emit + 0
      print "unjoined_emit_rows=" unjoined_emit_rows + 0

      print ""
      print "## Visibility Classification"
      print "selected_edge=call_materialization.created_body_backend_visibility"
      print "selected_cause=" selected_cause
      print "selected_rows=" selected_rows + 0
      print "classification=" classification
      print "[GENERATED_STAGE_CREATED_BODY_VISIBILITY] edge=call_materialization.created_body_backend_visibility owner=MaterializationTransaction old_edge=created_body_backend_missing classification=" classification " selected_cause=" selected_cause " selected_rows=" (selected_rows + 0) " next_action=" (classification == "eligible_visibility_edge" ? "write_behavior_receipt_for_selected_visibility_cause" : "stop_if_broad_or_ambiguous")

      print ""
      print "## Cause Buckets"
      if (cause_kinds == 0) {
        print "(none)"
      } else {
        for (cause in cause_count) {
          print "cause=" cause " rows=" cause_count[cause] + 0 " root_sized=" (((cause_count[cause] + 0) <= max_class_rows) ? 1 : 0)
        }
      }

      print ""
      print "## Cause Groups"
      if (group_total == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= group_total; i++) {
          key = group_order[i]
          print "group=" key " rows=" group_count[key] + 0 " root_sized=" (((group_count[key] + 0) <= max_class_rows) ? 1 : 0) " cause=" group_cause[key] " phase=" group_phase[key] " branch=" group_branch[key] " body_state=" group_body_state[key] " owner=" group_owner[key] " emitted_owner=" group_emitted_owner[key]
        }
      }

      print ""
      print "## Residual Samples"
      if ((sample_count["residual"] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count["residual"]; i++) {
          print sample["residual", i]
        }
      }

      print ""
      print "## Malformed Samples"
      if ((sample_count["malformed"] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count["malformed"]; i++) {
          print sample["malformed", i]
        }
      }
    }
  ' "$LOG_FILE"
)"

printf '%s\n' "$report"

classification="$(awk -F= '$1 == "classification" { value = $2 } END { print value }' <<<"$report")"

if [[ "${REQUIRE_CLASSIFIED:-0}" == "1" &&
      "$classification" == "rejected_unclassified_residual" ]]; then
  echo "FAIL: residual rows were not classified" >&2
  exit 9
fi

if [[ "${REQUIRE_ROOT_SIZED:-0}" == "1" &&
      "$classification" != "eligible_visibility_edge" ]]; then
  echo "FAIL: no root-sized created-body visibility edge selected" >&2
  exit 9
fi
