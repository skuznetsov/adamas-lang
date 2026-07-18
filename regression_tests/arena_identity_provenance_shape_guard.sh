#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ast_to_hir="${repo_root}/src/compiler/hir/ast_to_hir.cr"
arena_id="${repo_root}/src/compiler/semantic/identity/arena_id.cr"
def_identity="${repo_root}/src/compiler/semantic/identity/def_identity.cr"

rg -n 'class ArenaIdentityRegistry' "${arena_id}" >/dev/null
rg -n 'private def set_function_def_arena\(' "${ast_to_hir}" >/dev/null
rg -n 'arena_identity_registry!\.id_for\(arena\)' "${ast_to_hir}" >/dev/null
rg -n '@arena_identity_assert_enabled : Bool' "${ast_to_hir}" >/dev/null
rg -n '@arena_identity_assert_enabled = env_has\?\("ADAMAS_RESOLUTION_ASSERT"\)' "${ast_to_hir}" >/dev/null
rg -n 'arena_identity_registry!\.id_for\(arena\) if @arena_identity_assert_enabled' "${ast_to_hir}" >/dev/null
if rg -n '^\s*@arena_identity_registry\.id_for\(arena\)' "${ast_to_hir}" >/dev/null; then
  echo "arena identity registration must be assertion-gated" >&2
  exit 1
fi
rg -n 'private def unique_def_expr_index_for_provenance' "${ast_to_hir}" >/dev/null
rg -n 'private def provenance_candidate_arenas' "${ast_to_hir}" >/dev/null
rg -n 'private def canonical_def_identity_for_provenance' "${ast_to_hir}" >/dev/null
rg -n 'canonical_def_identity_for_provenance\(res\.def_node, @arena\)' "${ast_to_hir}" >/dev/null
rg -n 'env_has\?\("ADAMAS_RESOLUTION_ASSERT"\)' "${ast_to_hir}" >/dev/null
rg -n 'self\.from_arena_id\(arena_id : ArenaId' "${def_identity}" >/dev/null
rg -n 'ArenaId registry exhausted' "${arena_id}" >/dev/null

if rg -n 'Hash\(String, (ArenaId|DefIdentity)' "${repo_root}/src/compiler" >/dev/null; then
  echo "arena identity must not be keyed by rendered String" >&2
  exit 1
fi

echo "arena identity provenance source shape: PASS"
