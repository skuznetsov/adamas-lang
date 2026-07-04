#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
REQUIRE_METHOD_BODY_SCOPE="${REQUIRE_METHOD_BODY_SCOPE:-0}"
REQUIRE_LOWER_DEF_BODY_SCOPE="${REQUIRE_LOWER_DEF_BODY_SCOPE:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/method_body_lowering_scope_source_shape_guard.sh
env:
  REQUIRE_METHOD_BODY_SCOPE=0|1
  REQUIRE_LOWER_DEF_BODY_SCOPE=0|1

Behavior-neutral source-shape guard for the MethodBodyLoweringScope owner edge.
The first slice was scoped to AstToHir#lower_method. The lower_def extension is
reported separately so proc/module-method manual scopes remain explicit
residual debt, not silently migrated.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

report="$(
  awk '
    function reset_current() {
      current = ""
    }

    function record_line(prefix) {
      if (index($0, "enter_method_body_lowering_scope(") > 0) {
        enter[prefix]++
      }
      if (index($0, "restore_method_body_lowering_scope(") > 0) {
        restore[prefix]++
      }
      if (index($0, "saved_yield_block_stack") > 0 ||
          index($0, "saved_yield_arena_stack") > 0 ||
          index($0, "saved_yield_param_stack") > 0 ||
          index($0, "saved_yield_return_stack") > 0 ||
          index($0, "saved_yield_block_return_stack") > 0 ||
          index($0, "saved_yield_name_stack") > 0 ||
          index($0, "saved_inline_arenas") > 0 ||
          index($0, "saved_infer_body_context") > 0 ||
          index($0, "saved_def_return_type") > 0) {
        legacy[prefix]++
      }
    }

    function shape_for(prefix) {
      if (enter[prefix] > 0 && restore[prefix] > 0 && legacy[prefix] == 0) {
        return "method_body_scope_owner_consumed"
      }
      if (legacy[prefix] > 0) {
        return "legacy_method_body_ambient_scope"
      }
      return "missing_method_body_scope_edge"
    }

    /private def lower_method\(/ {
      current = "lower_method"
      next
    }

    /def lower_def\(/ {
      current = "lower_def"
      next
    }

    current != "" && /^    (private )?def / {
      reset_current()
    }

    current != "" {
      record_line(current)
    }

    END {
      lower_method_shape = shape_for("lower_method")
      lower_def_shape = shape_for("lower_def")

      print "source_shape=" lower_method_shape
      print "lower_method_source_shape=" lower_method_shape
      print "lower_method_enter_scope_calls=" (enter["lower_method"] + 0)
      print "lower_method_restore_scope_calls=" (restore["lower_method"] + 0)
      print "lower_method_legacy_scope_saves=" (legacy["lower_method"] + 0)
      print "lower_def_source_shape=" lower_def_shape
      print "lower_def_enter_scope_calls=" (enter["lower_def"] + 0)
      print "lower_def_restore_scope_calls=" (restore["lower_def"] + 0)
      print "lower_def_legacy_scope_saves=" (legacy["lower_def"] + 0)
    }
  ' "$SOURCE_FILE"
)"

printf '%s\n' "$report"
source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"

if [[ "$REQUIRE_METHOD_BODY_SCOPE" == "1" && "$source_shape" != "method_body_scope_owner_consumed" ]]; then
  echo "FAIL: expected method_body_scope_owner_consumed, got $source_shape" >&2
  exit 9
fi

lower_def_source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "lower_def_source_shape" { print $2; exit }')"
if [[ "$REQUIRE_LOWER_DEF_BODY_SCOPE" == "1" && "$lower_def_source_shape" != "method_body_scope_owner_consumed" ]]; then
  echo "FAIL: expected lower_def method_body_scope_owner_consumed, got $lower_def_source_shape" >&2
  exit 10
fi

echo "PASS: MethodBodyLoweringScope source-shape status=$source_shape"
