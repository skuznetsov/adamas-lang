#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
REQUIRE_PROVEN_ACCESSORS="${REQUIRE_PROVEN_ACCESSORS:-0}"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/expansion_accessor_provenance_source_shape_guard.sh
env:
  REQUIRE_PROVEN_ACCESSORS=0|1

Source-shape guard for accessor nodes recovered from class-member expansions
or materialized accessor macro calls. Each case arm must pass a concrete
GetterNode, SetterNode, or PropertyNode binding into
register_accessors_in_class instead of leaking a broad Node binding.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

report="$(
  awk '
    /private def register_class_members_from_expansion\(/ {
      in_helper = 1
      next
    }

    in_helper && /^    (private )?def / {
      in_helper = 0
    }

    in_helper {
      if ($0 ~ /expanded_getter = member\.unsafe_as\(Adamas::Compiler::Frontend::GetterNode\)/) {
        proof_bindings++
      }
      if ($0 ~ /expanded_setter = member\.unsafe_as\(Adamas::Compiler::Frontend::SetterNode\)/) {
        proof_bindings++
      }
      if ($0 ~ /expanded_property = member\.unsafe_as\(Adamas::Compiler::Frontend::PropertyNode\)/) {
        proof_bindings++
      }
      if ($0 ~ /paired_getter = accessor\.unsafe_as\(Adamas::Compiler::Frontend::GetterNode\)/) {
        proof_bindings++
      }
      if ($0 ~ /paired_setter = accessor\.unsafe_as\(Adamas::Compiler::Frontend::SetterNode\)/) {
        proof_bindings++
      }
      if ($0 ~ /paired_property = accessor\.unsafe_as\(Adamas::Compiler::Frontend::PropertyNode\)/) {
        proof_bindings++
      }
      if ($0 ~ /register_accessors_in_class\((expanded|paired)_(getter|setter|property), class_name, ivars, offset_ref\)/) {
        proven_consumers++
      }
      if ($0 ~ /register_accessors_in_class\(/) {
        total_consumers++
      }
      if ($0 ~ /register_accessors_in_class\((member|accessor), class_name, ivars, offset_ref\)/) {
        broad_consumers++
      }
    }

    END {
      if (proof_bindings == 6 && proven_consumers == 6 && total_consumers == 6 && broad_consumers == 0) {
        source_shape = "proven_expansion_accessors_consumed"
      } else if (proof_bindings == 0 && proven_consumers == 0 && total_consumers == 4 && broad_consumers == 4) {
        source_shape = "broad_expansion_accessor_leaked"
      } else if (proof_bindings == 3 && proven_consumers == 3 && total_consumers == 4 && broad_consumers == 1) {
        source_shape = "partial_expansion_accessor_provenance"
      } else {
        source_shape = "ambiguous_expansion_accessor_provenance"
      }

      print "source_shape=" source_shape
      print "proof_bindings=" (proof_bindings + 0)
      print "proven_consumers=" (proven_consumers + 0)
      print "total_consumers=" (total_consumers + 0)
      print "broad_consumers=" (broad_consumers + 0)
    }
  ' "$SOURCE_FILE"
)"

printf '%s\n' "$report"
source_shape="$(printf '%s\n' "$report" | awk -F= '$1 == "source_shape" { print $2; exit }')"

if [[ "$REQUIRE_PROVEN_ACCESSORS" == "1" && "$source_shape" != "proven_expansion_accessors_consumed" ]]; then
  echo "FAIL: expected proven_expansion_accessors_consumed, got $source_shape" >&2
  exit 9
fi

echo "PASS: expansion accessor provenance source-shape status=$source_shape"
