#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SAMPLES="${SAMPLES:-12}"

if [[ ! -d "$ROOT_DIR/src/compiler" ]]; then
  echo "usage: $0 [repo-root]" >&2
  echo "error: $ROOT_DIR does not look like the Adamas repo root" >&2
  exit 2
fi

cd "$ROOT_DIR"

COMPILER_FILES=(
  src/compiler/cli.cr
  src/compiler/hir/ast_to_hir.cr
  src/compiler/mir/hir_to_mir.cr
  src/compiler/mir/llvm_backend.cr
  src/compiler/mir/mir.cr
  src/compiler/layout_contract.cr
)

section() {
  printf '\n## %s\n' "$1"
}

census() {
  local name="$1"
  local pattern="$2"

  section "$name"
  echo "files: ${COMPILER_FILES[*]}"
  echo "pattern: $pattern"

  local count
  count="$({ rg -n --no-heading -e "$pattern" "${COMPILER_FILES[@]}" 2>/dev/null || true; } | wc -l | tr -d ' ')"
  echo "hits: $count"

  if [[ "$count" != "0" ]]; then
    { rg -n --no-heading -e "$pattern" "${COMPILER_FILES[@]}" 2>/dev/null || true; } | head -n "$SAMPLES"
  fi
}

echo "# CodePathStatus Census"
echo "repo: $ROOT_DIR"
echo "samples_per_section: $SAMPLES"
echo "note: static grep only; this is Phase 1b input, not a dead/live proof"
echo "statuses: live | suspected_dead | legacy_shim | debug_only | delete_ready"
echo "rule: no row becomes delete_ready without runtime census plus protecting falsifier"

census \
  "Env/debug/probe gates" \
  "env_get\\(|env_has\\?|env_enabled\\?|ADAMAS_[A-Z0-9_]+|DEBUG_[A-Z0-9_]+|TRACE_[A-Z0-9_]+|STAGE2_DEBUG"

census \
  "Bootstrap workaround comments" \
  "V2 safety|V2 BOOTSTRAP|bootstrap|self-host|workaround|temporary|TODO|FIXME|HACK|fragile"

census \
  "Fallback and recovery paths" \
  "fallback|recover|repair|unknown|best_effort|default_.*value|fail_closed|emit_dead_code_stub|record_undefined_extern|STUB CALLED|ExternCall"

census \
  "Legacy/shim naming surfaces" \
  "legacy|shim|compat|override|requested_name|target_name|materialized_name|call_symbol|materialization"

census \
  "Broad semantic scans and containment heuristics" \
  "arena_for_expr\\?|@main_arenas|@inline_arenas|index < .*\\.size|find_.*owner|scan|guess|heuristic"

census \
  "Backend semantic leakage candidates" \
  "parse_method_name|mangle_function_name|strip_type_suffix|fixup_call_arg_types|default_phi_value|record_undefined_extern|@undefined_externs|@func_by_name"

census \
  "Layout/ABI workaround candidates" \
  "inline_container|primitive_tuple|carrier|slot_repr|slot_size|storage_context|LayoutContract|AbiContract|pointer-carrier|heap-alloc"

