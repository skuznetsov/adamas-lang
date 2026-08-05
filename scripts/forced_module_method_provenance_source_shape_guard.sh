#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
REQUIRE_PROVEN_MODULE_DEF="${REQUIRE_PROVEN_MODULE_DEF:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/forced_module_method_provenance_source_shape_guard.sh
env:
  REQUIRE_PROVEN_MODULE_DEF=0|1

Source-shape guard for the forced module-method provenance boundary. A
successful lookup must pass the proven non-null DefNode binding into
lower_module_method instead of leaking the original optional lookup result.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

report="$(
  awk '
    /private def force_lower_module_method_by_name\(/ {
      in_helper = 1
      next
    }

    in_helper && /^    (private )?def / {
      in_helper = 0
    }

    in_helper {
      if ($0 ~ /resolved_func_def = func_def \|\| return/) {
        proof_bindings++
      }
      if ($0 ~ /lower_module_method\(owner, resolved_func_def, nil, nil, nil, name\)/) {
        proven_consumers++
      }
      if ($0 ~ /lower_module_method\(owner, func_def, nil, nil, nil, name\)/) {
        optional_consumers++
      }
    }

    END {
      if (proof_bindings == 1 && proven_consumers == 1 && optional_consumers == 0) {
        source_shape = "proven_module_def_consumed"
      } else if (proof_bindings == 1 && proven_consumers == 0 && optional_consumers == 1) {
        source_shape = "optional_module_def_leaked"
      } else {
        source_shape = "ambiguous_forced_module_method_provenance"
      }

      print "source_shape=" source_shape
      print "proof_bindings=" (proof_bindings + 0)
      print "proven_consumers=" (proven_consumers + 0)
      print "optional_consumers=" (optional_consumers + 0)
    }
  ' "$SOURCE_FILE"
)"

printf '%s\n' "$report"
source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"

if [[ "$REQUIRE_PROVEN_MODULE_DEF" == "1" && "$source_shape" != "proven_module_def_consumed" ]]; then
  echo "FAIL: expected proven_module_def_consumed, got $source_shape" >&2
  exit 9
fi

echo "PASS: forced module-method provenance source-shape status=$source_shape"
