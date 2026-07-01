#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SAMPLES="${SAMPLES:-8}"

if [[ ! -d "$ROOT_DIR/src/compiler" ]]; then
  echo "usage: $0 [repo-root]" >&2
  echo "error: $ROOT_DIR does not look like the Adamas repo root" >&2
  exit 2
fi

cd "$ROOT_DIR"

section() {
  printf '\n## %s\n' "$1"
}

census() {
  local name="$1"
  local files="$2"
  local pattern="$3"

  section "$name"
  echo "files: $files"
  echo "pattern: $pattern"

  # Keep this script read-only and grep-based. It is an architecture census,
  # not a semantic proof; every promoted row needs a follow-up dynamic ledger.
  local count
  count="$({ rg -n --no-heading -e "$pattern" $files 2>/dev/null || true; } | wc -l | tr -d ' ')"
  echo "hits: $count"

  if [[ "$count" != "0" ]]; then
    { rg -n --no-heading -e "$pattern" $files 2>/dev/null || true; } | head -n "$SAMPLES"
  fi
}

echo "# Semantic Decision Census"
echo "repo: $ROOT_DIR"
echo "samples_per_section: $SAMPLES"
echo "note: static grep only; use as Phase 1 owner-map input, not as VERIFIED liveness evidence"

census \
  "NameResolution / symbol spelling" \
  "src/compiler/hir/ast_to_hir.cr src/compiler/cli.cr" \
  "parse_method_name|mangle_function_name|strip_type_suffix|@current_class|@current_namespace|registered_compiler_nested_type_alias|resolve_type_name|type_ref_for_name|path_join|File\\.expand_path|safe_dirname"

census \
  "TypeIdentity / registration" \
  "src/compiler/hir/ast_to_hir.cr src/compiler/mir/hir_to_mir.cr src/compiler/mir/mir.cr" \
  "@class_info|@generic_templates|@generic_reopenings|register_class|register_struct|register_module|intern_type|TypeDescriptor|type_registry|get_or_create_type|register_concrete"

census \
  "AstNodeIdentity / arena ownership" \
  "src/compiler/hir/ast_to_hir.cr" \
  "with_arena|arena_for_expr|node_for_expr|node_for_call_expr|@arena\\[|@main_arenas|@inline_arenas|source_for_arena"

census \
  "SemanticStateScope / ambient maps" \
  "src/compiler/hir/ast_to_hir.cr" \
  "@type_param_map|with_type_param_map|with_isolated_type_param_map|function_type_param_map_for|@function_type_param_maps|def_has_untyped_regular_param|raw_annotation_needs_callsite_specialization|current_type_param"

census \
  "CallResolution / overload choice" \
  "src/compiler/hir/ast_to_hir.cr" \
  "resolve_method_call|lookup_function_def_for_call|resolve_call_tuple|params_match_score|declared_type_match_score|prefer_callsite_specialization|overload|candidate|named_arg|block_arg"

census \
  "Materialization / pending body identity" \
  "src/compiler/hir/ast_to_hir.cr src/compiler/mir/hir_to_mir.cr" \
  "lower_function_if_needed|pending_function|@pending_lower_functions|@pending_function_queue|remember_callsite_arg_types|materialized_name|target_name|requested_name|shape_keyed_block|@block_shape_specializations|ExternCall"

census \
  "AbiFacts / LayoutContract" \
  "src/compiler/hir/ast_to_hir.cr src/compiler/mir/hir_to_mir.cr src/compiler/mir/llvm_backend.cr src/compiler/layout_contract.cr" \
  "LayoutContract|AbiContract|lower_field_get|lower_field_set|storage_context|inline_container|field_offset|carrier|copy_plan|load_plan|store_plan|canonical_ivar_storage|primitive_tuple"

census \
  "Backend semantic leakage" \
  "src/compiler/mir/llvm_backend.cr" \
  "parse_method_name|mangle_function_name|strip_type_suffix|emit_extern_call|record_undefined_extern|@func_by_name|@emitted_functions|default_phi_value|fixup_call_arg_types|materialized|target"

census \
  "Debug gates / workaround surface" \
  "src/compiler/cli.cr src/compiler/hir/ast_to_hir.cr src/compiler/mir/hir_to_mir.cr src/compiler/mir/llvm_backend.cr" \
  "env_enabled\\?|ADAMAS_[A-Z0-9_]+|DEBUG_|TRACE_|TODO|workaround|V2 BOOTSTRAP|STAGE2_DEBUG|bootstrap"
