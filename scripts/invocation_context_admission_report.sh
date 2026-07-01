#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"

PREFERRED_SEAM="${PREFERRED_SEAM:-lower_super.previous_def.invocation_context}"
REQUIRE_PROMOTED="${REQUIRE_PROMOTED:-0}"
SAMPLES="${SAMPLES:-12}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/invocation_context_admission_report.sh
env:
  PREFERRED_SEAM=lower_super.previous_def.invocation_context
  REQUIRE_PROMOTED=0|1
  SAMPLES=12

Behavior-neutral source-shape gate for the InvocationContext / InlineYieldFrame
row. It selects the super/previous_def context seam and prevents lower_super
crash-stack patches or standalone context ledgers from counting as architecture
progress.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

count_source_shape() {
  awk -v samples="$SAMPLES" '
    function enter(name) {
      in_method = name
    }

    function leave_if_needed(line) {
      if (in_method != "" && line ~ /^    private def /) {
        in_method = ""
      }
    }

    function keep_sample(kind, row) {
      if (sample_count[kind] < samples) {
        sample_count[kind]++
        sample[kind, sample_count[kind]] = row
      }
    }

    function scan_line(line, row) {
      code = line
      sub(/[[:space:]]+#.*/, "", code)

      if (code ~ /@current_class/ || code ~ /@current_method([^A-Za-z0-9_]|$)/) {
        ambient_owner_method++
        method_ambient_owner_method[in_method]++
        keep_sample("ambient_owner_method", in_method ":" NR ":" row)
      }
      if (code ~ /@current_method_is_class/) {
        ambient_kind++
        method_ambient_kind[in_method]++
        keep_sample("ambient_kind", in_method ":" NR ":" row)
      }
      if (code ~ /@current_super_source_module/) {
        ambient_super_source++
        method_ambient_super_source[in_method]++
        keep_sample("ambient_super_source", in_method ":" NR ":" row)
      }
      if (code ~ /current_method_forward_arg_ids\(ctx\)/) {
        direct_forward_policy++
        method_forward_policy[in_method]++
        keep_sample("direct_forward_policy", in_method ":" NR ":" row)
      }
      if (code ~ /InvocationContext/ || code ~ /InlineYieldFrame/ || code ~ /invocation_context/ || code ~ /inline_yield_frame/) {
        helper++
        method_helper[in_method]++
        keep_sample("helper", in_method ":" NR ":" row)
      }
    }

    /^    private def lower_super\(ctx : LoweringContext,/ {
      enter("lower_super")
      next
    }

    /^    private def lower_previous_def\(ctx : LoweringContext,/ {
      enter("lower_previous_def")
      next
    }

    {
      leave_if_needed($0)
      if (in_method != "") {
        scan_line($0, $0)
      }
    }

    END {
      direct = ambient_owner_method + ambient_kind + ambient_super_source + direct_forward_policy

      if (helper > 0 && direct == 0 &&
          method_helper["lower_super"] > 0 &&
          method_helper["lower_previous_def"] > 0) {
        source_shape = "already_promoted_shadow"
      } else if (direct > 0 && helper == 0) {
        source_shape = "legacy_ambient_context_edge"
      } else if (direct > 0 && helper > 0) {
        source_shape = "partial_invocation_context_authority"
      } else {
        source_shape = "missing_expected_edge"
      }

      print "source_shape=" source_shape
      print "ambient_owner_method_count=" ambient_owner_method + 0
      print "ambient_kind_count=" ambient_kind + 0
      print "ambient_super_source_count=" ambient_super_source + 0
      print "direct_forward_policy_count=" direct_forward_policy + 0
      print "invocation_helper_count=" helper + 0
      print "lower_super_ambient_owner_method_count=" method_ambient_owner_method["lower_super"] + 0
      print "lower_super_ambient_kind_count=" method_ambient_kind["lower_super"] + 0
      print "lower_super_ambient_super_source_count=" method_ambient_super_source["lower_super"] + 0
      print "lower_super_forward_policy_count=" method_forward_policy["lower_super"] + 0
      print "lower_super_helper_count=" method_helper["lower_super"] + 0
      print "lower_previous_def_ambient_owner_method_count=" method_ambient_owner_method["lower_previous_def"] + 0
      print "lower_previous_def_ambient_kind_count=" method_ambient_kind["lower_previous_def"] + 0
      print "lower_previous_def_ambient_super_source_count=" method_ambient_super_source["lower_previous_def"] + 0
      print "lower_previous_def_forward_policy_count=" method_forward_policy["lower_previous_def"] + 0
      print "lower_previous_def_helper_count=" method_helper["lower_previous_def"] + 0

      print "sample_ambient_owner_method_count=" sample_count["ambient_owner_method"] + 0
      for (idx = 1; idx <= sample_count["ambient_owner_method"]; idx++) {
        print "sample_ambient_owner_method_" idx "=" sample["ambient_owner_method", idx]
      }
      print "sample_ambient_kind_count=" sample_count["ambient_kind"] + 0
      for (idx = 1; idx <= sample_count["ambient_kind"]; idx++) {
        print "sample_ambient_kind_" idx "=" sample["ambient_kind", idx]
      }
      print "sample_ambient_super_source_count=" sample_count["ambient_super_source"] + 0
      for (idx = 1; idx <= sample_count["ambient_super_source"]; idx++) {
        print "sample_ambient_super_source_" idx "=" sample["ambient_super_source", idx]
      }
      print "sample_direct_forward_policy_count=" sample_count["direct_forward_policy"] + 0
      for (idx = 1; idx <= sample_count["direct_forward_policy"]; idx++) {
        print "sample_direct_forward_policy_" idx "=" sample["direct_forward_policy", idx]
      }
      print "sample_helper_count=" sample_count["helper"] + 0
      for (idx = 1; idx <= sample_count["helper"]; idx++) {
        print "sample_helper_" idx "=" sample["helper", idx]
      }
    }
  ' "$SOURCE_FILE"
}

report="$(count_source_shape)"
source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"

selection_status="rejected"
case "$PREFERRED_SEAM:$source_shape" in
  lower_super.previous_def.invocation_context:legacy_ambient_context_edge)
    selection_status="eligible_invocation_context_owner"
    ;;
  lower_super.previous_def.invocation_context:already_promoted_shadow)
    selection_status="already_promoted_shadow"
    ;;
  lower_super.previous_def.invocation_context:partial_invocation_context_authority)
    selection_status="rejected_partial_invocation_context_authority"
    ;;
  lower_super.previous_def.invocation_context:missing_expected_edge)
    selection_status="rejected_missing_source_edge"
    ;;
esac

echo "# InvocationContext Admission Report"
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
echo "[INVOCATION_CONTEXT_ADMISSION] seam=lower_super.previous_def.invocation_context owner=InvocationContext/InlineYieldFrame old_edge=ambient_current_class_method_super_and_forward_policy owned_edge=InvocationContext source_shape=$source_shape selection_status=$selection_status next_action=source_shape_then_shadow_parity_helper"
echo ""
echo "## Samples"
printf '%s\n' "$report" | awk -F= '
  $1 ~ /^sample_/ {
    print
  }
'

if [[ "$selection_status" == "rejected_missing_source_edge" ]]; then
  echo "FAIL: preferred InvocationContext seam source shape is missing" >&2
  exit 1
fi

if [[ "$selection_status" == "rejected_partial_invocation_context_authority" ]]; then
  echo "FAIL: partial InvocationContext authority detected" >&2
  exit 1
fi

if [[ "$REQUIRE_PROMOTED" == "1" && "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: preferred InvocationContext seam is not promoted yet" >&2
  exit 9
fi

if [[ "$selection_status" != "eligible_invocation_context_owner" &&
      "$selection_status" != "already_promoted_shadow" ]]; then
  echo "FAIL: no InvocationContext seam selected" >&2
  exit 1
fi
