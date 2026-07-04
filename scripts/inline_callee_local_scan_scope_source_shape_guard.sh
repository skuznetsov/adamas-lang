#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE="${REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/inline_callee_local_scan_scope_source_shape_guard.sh
env:
  REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE=0|1

Behavior-neutral source-shape guard for the InlineCalleeLocalScanScope owner
edge. It is intentionally scoped to AstToHir#inline_callee_local_names, where
the callee-local scanner temporarily switches arenas and clears inline-yield
block stacks before collecting assigned/block-local names.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

report="$(
  awk '
    /private def inline_callee_local_names\(/ {
      in_scan = 1
      next
    }

    in_scan && /^    private def / {
      in_scan = 0
    }

    in_scan {
      if (index($0, "enter_inline_callee_local_scan_scope(") > 0) {
        enter_calls++
      }
      if (index($0, "restore_inline_callee_local_scan_scope(") > 0) {
        restore_calls++
      }
      if (index($0, "old_arena") > 0 ||
          index($0, "saved_inline_yield_block_stack") > 0 ||
          index($0, "saved_inline_yield_block_arena_stack") > 0 ||
          index($0, "saved_inline_yield_block_param_types_stack") > 0) {
        legacy_saves++
      }
    }

    END {
      if (enter_calls > 0 && restore_calls > 0 && legacy_saves == 0) {
        source_shape = "inline_callee_local_scan_scope_consumed"
      } else if (legacy_saves > 0) {
        source_shape = "legacy_inline_callee_local_scan_ambient_scope"
      } else {
        source_shape = "missing_inline_callee_local_scan_scope_edge"
      }

      print "source_shape=" source_shape
      print "inline_scan_enter_scope_calls=" (enter_calls + 0)
      print "inline_scan_restore_scope_calls=" (restore_calls + 0)
      print "inline_scan_legacy_scope_saves=" (legacy_saves + 0)
    }
  ' "$SOURCE_FILE"
)"

printf '%s\n' "$report"

source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"
if [[ "$REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE" == "1" && "$source_shape" != "inline_callee_local_scan_scope_consumed" ]]; then
  echo "FAIL: expected inline_callee_local_scan_scope_consumed, got $source_shape" >&2
  exit 9
fi

echo "PASS: InlineCalleeLocalScanScope source-shape status=$source_shape"
