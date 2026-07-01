#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"

PREFERRED_SEAM="${PREFERRED_SEAM:-lower_function_if_needed.exact_lookup_keep_requested_name}"
REQUIRE_PROMOTED="${REQUIRE_PROMOTED:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/method_name_codec_admission_report.sh
env:
  PREFERRED_SEAM=lower_function_if_needed.exact_lookup_keep_requested_name
  REQUIRE_PROMOTED=0|1

Behavior-neutral source-shape gate for the NameResolution/MethodNameCodec row.
It selects one rendered-name authority edge for a future shadow/parity helper.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

source_shape_for_exact_lookup() {
  awk '
    /private def lower_function_if_needed_impl\(name : String\)/ {
      in_method = 1
      next
    }
    in_method && /private def / {
      in_method = 0
    }
    in_method {
      if (index($0, "method_name_codec_exact_lookup_keep_requested_name?") > 0) {
        helper_call = 1
      }
      if (index($0, "requested_has_concrete_type = name.includes?") > 0) {
        old_requested_suffix = 1
      }
      if (index($0, "resolved_is_arity_wildcard = resolved_entry_name.includes?") > 0) {
        old_resolved_arity = 1
      }
      if (index($0, "target_name = keep_requested_name ? name : resolved_entry_name") > 0) {
        exact_assignment = 1
      }
    }
    END {
      if (helper_call && !old_requested_suffix && !old_resolved_arity && exact_assignment) {
        print "already_promoted_shadow"
      } else if (old_requested_suffix && old_resolved_arity && exact_assignment) {
        print "legacy_string_edge"
      } else {
        print "missing_expected_edge"
      }
    }
  ' "$SOURCE_FILE"
}

count_literal() {
  local pattern="$1"
  grep -F -c "$pattern" "$SOURCE_FILE" || true
}

exact_shape="$(source_shape_for_exact_lookup)"
exact_old_suffix_count="$(count_literal "requested_has_concrete_type = name.includes?")"
exact_old_arity_count="$(count_literal "resolved_is_arity_wildcard = resolved_entry_name.includes?")"
exact_helper_count="$(count_literal "method_name_codec_exact_lookup_keep_requested_name?")"
callsite_keep_count="$(count_literal "\"lower_function_if_needed.callsite_args\"")"
suffix_keep_count="$(count_literal "\"lower_function_if_needed.suffix_types\"")"
method_suffix_count="$(count_literal "private def method_suffix(name : String)")"
method_owner_from_name_count="$(count_literal "private def method_owner_from_name(name : String)")"

selection_status="rejected"
case "$PREFERRED_SEAM:$exact_shape" in
  lower_function_if_needed.exact_lookup_keep_requested_name:legacy_string_edge)
    selection_status="eligible_codec_owner"
    ;;
  lower_function_if_needed.exact_lookup_keep_requested_name:already_promoted_shadow)
    selection_status="already_promoted_shadow"
    ;;
  lower_function_if_needed.exact_lookup_keep_requested_name:missing_expected_edge)
    selection_status="rejected_missing_source_edge"
    ;;
esac

echo "# MethodNameCodec Admission Report"
echo "source: $SOURCE_FILE"
echo "preferred_seam: $PREFERRED_SEAM"
echo "preferred_source_shape: $exact_shape"
echo "require_promoted: $REQUIRE_PROMOTED"
echo "note: source-shape selection only; no compiler behavior changes"
echo ""
echo "## Counts"
echo "exact_old_requested_suffix_count=$exact_old_suffix_count"
echo "exact_old_resolved_arity_count=$exact_old_arity_count"
echo "exact_helper_count=$exact_helper_count"
echo "callsite_keep_marker_count=$callsite_keep_count"
echo "suffix_keep_marker_count=$suffix_keep_count"
echo "method_suffix_helper_count=$method_suffix_count"
echo "method_owner_from_name_helper_count=$method_owner_from_name_count"
echo ""
echo "## Candidate Selection"
echo "[METHOD_NAME_CODEC_ADMISSION] seam=lower_function_if_needed.exact_lookup_keep_requested_name owner=NameResolution/MethodNameCodec old_edge=rendered_suffix_and_arity_checks owned_edge=method_name_codec_exact_lookup_keep_requested_name source_shape=$exact_shape selection_status=$selection_status next_action=shadow_parity_helper"
echo "[METHOD_NAME_CODEC_ADMISSION] seam=lower_function_if_needed.callsite_args_keep_requested_name owner=NameResolution/MethodNameCodec old_edge=mixed_state_scope_and_suffix_checks owned_edge=unselected source_shape=legacy_mixed selection_status=rejected_later_state_scope_mixed next_action=none"
echo "[METHOD_NAME_CODEC_ADMISSION] seam=lower_function_if_needed.suffix_types_keep_requested_name owner=NameResolution/MethodNameCodec old_edge=mixed_state_scope_and_suffix_checks owned_edge=unselected source_shape=legacy_mixed selection_status=rejected_later_state_scope_mixed next_action=none"
echo "[METHOD_NAME_CODEC_ADMISSION] seam=method_suffix_helper owner=NameResolution/MethodNameCodec old_edge=low_level_suffix_slice_helper owned_edge=unselected source_shape=legacy_helper selection_status=rejected_low_level_helper next_action=none"
echo "[METHOD_NAME_CODEC_ADMISSION] seam=method_owner_from_name_helper owner=NameResolution/MethodNameCodec old_edge=low_level_owner_slice_helper owned_edge=unselected source_shape=legacy_helper selection_status=rejected_low_level_helper next_action=none"

if [[ "$selection_status" == "rejected_missing_source_edge" ]]; then
  echo "FAIL: preferred MethodNameCodec seam source shape is missing" >&2
  exit 1
fi

if [[ "$REQUIRE_PROMOTED" == "1" && "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: preferred MethodNameCodec seam is not promoted yet" >&2
  exit 9
fi

if [[ "$selection_status" != "eligible_codec_owner" &&
      "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: no MethodNameCodec seam selected" >&2
  exit 1
fi
