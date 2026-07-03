#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
REQUIRE_METHOD_BODY_SCOPE="${REQUIRE_METHOD_BODY_SCOPE:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/method_body_lowering_scope_source_shape_guard.sh
env:
  REQUIRE_METHOD_BODY_SCOPE=0|1

Behavior-neutral source-shape guard for the MethodBodyLoweringScope owner edge.
It is intentionally scoped to AstToHir#lower_method: lower_def/proc-lowering
manual scopes are residual debt, not part of this B5 slice.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

report="$(
  awk '
    /private def lower_method\(/ {
      in_method = 1
      next
    }

    in_method && /^    private def / {
      in_method = 0
    }

    in_method {
      if (index($0, "enter_method_body_lowering_scope(") > 0) {
        enter_calls++
      }
      if (index($0, "restore_method_body_lowering_scope(") > 0) {
        restore_calls++
      }
      if (index($0, "saved_yield_block_stack") > 0 ||
          index($0, "saved_yield_arena_stack") > 0 ||
          index($0, "saved_yield_param_stack") > 0 ||
          index($0, "saved_yield_return_stack") > 0 ||
          index($0, "saved_yield_name_stack") > 0 ||
          index($0, "saved_inline_arenas") > 0 ||
          index($0, "saved_infer_body_context") > 0 ||
          index($0, "saved_def_return_type") > 0) {
        legacy_saves++
      }
    }

    END {
      if (enter_calls > 0 && restore_calls > 0 && legacy_saves == 0) {
        source_shape = "method_body_scope_owner_consumed"
      } else if (legacy_saves > 0) {
        source_shape = "legacy_method_body_ambient_scope"
      } else {
        source_shape = "missing_method_body_scope_edge"
      }

      print "source_shape=" source_shape
      print "lower_method_enter_scope_calls=" (enter_calls + 0)
      print "lower_method_restore_scope_calls=" (restore_calls + 0)
      print "lower_method_legacy_scope_saves=" (legacy_saves + 0)
    }
  ' "$SOURCE_FILE"
)"

printf '%s\n' "$report"
source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"

if [[ "$REQUIRE_METHOD_BODY_SCOPE" == "1" && "$source_shape" != "method_body_scope_owner_consumed" ]]; then
  echo "FAIL: expected method_body_scope_owner_consumed, got $source_shape" >&2
  exit 9
fi

echo "PASS: MethodBodyLoweringScope source-shape status=$source_shape"
