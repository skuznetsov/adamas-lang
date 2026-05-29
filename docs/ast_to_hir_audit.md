# `ast_to_hir.cr` — audit index (no full re-read)

**Source:** `src/compiler/hir/ast_to_hir.cr` in the `adamas_repo` repository (`bootstrap-benchmark` branch).  
**Size:** 74,660 lines (single file).  
**Generated:** automated structure scan + spot reads; after editing the source file, regenerate the “Statistics” and “lower_* index” sections.

---

## 1. Purpose of this document

- Quickly locate **where** a topic lives in the huge file (line anchors and name prefixes).
- Avoid memorizing **74k lines** — a **layer map** and **entry points** are enough.
- When debugging: `rg -n "def lower_<...>" ast_to_hir.cr` starting from this index.

---

## 2. File layout (top level)

| Lines (approx.) | Entity | Role |
|-----------------|--------|------|
| 1–22 | `require`, `LibMachVM` (darwin) | Dependencies; optional Mach probe for address checks. |
| 23–24 | `module Crystal::HIR` | HIR module root. |
| 25–33 | `LoweringError` | Lowering exception. |
| 35–259 | `LoweringContext` | Context for **one** HIR function: blocks, locals, `emit`/`type_of`, scope stack. **29** methods at 4-space indent. |
| 261–323 | module-level `record` / `private struct` | Metadata: `IVarInfo`, `ClassInfo`, `ClassAccessorEntry`, `GenericClassTemplate`, `DeferredModuleContext`, timing structs, etc. |
| 325–74660 | `class AstToHir` | Main AST→HIR lowering. |

---

## 3. `LoweringContext` — fixed facts

- Holds **`@function`**, **`@module`**, **`@arena`**, current block, scope stack, type cache, maps `value_id → type` and `value_id → Value`.
- **`emit` / `emit_to_block`**: for `Literal(nil)` with a user type — tracks `@type_literal_values`; optional trace **`ADAMAS_TRACE_SHOVEL_TYPES`** for one debug-only function.
- **`get_type(String)`**: maps primitive names to `TypeRef::*`, otherwise `intern_type` via descriptor.

---

## 4. `AstToHir` — nested types (4 spaces: `class`/`struct`/`enum`)

Line numbers are approximate; if the file shifts, re-check with `rg -n "^    (private )?(class|struct|enum) "`.

| Line | Name | Role |
|------|------|------|
| 331 | `GenericOwnerInfo` | Avoids NamedTuple runtime in V2. |
| 344 | `GenericSplitInfo` | Indexable generic name “split” (`[]` by Symbol). |
| 370 | `CallSignature` | Call signature for lookup. |
| 381 | `DefParamStats` | Def parameter statistics. |
| 416 | `InitParamsCapture` | Init parameter capture. |
| 429–543 | `MethodNameParts`, lookup key caches | Parse mangled name `Owner#m$T` / caching. |
| 1461 | `FunctionLoweringState` | FSM state while lowering a function. |
| 2573–2581 | `ResolvedTypeNameCacheEntry`, `TypeNameExistsCacheEntry` | Type name caches. |
| 2666–2691 | `InlineReturnContext`, `InlineReturnOverride`, `InlineNextContext` | Inline next/return in blocks. |
| 29831 | `ASTCallInfo` | Metadata for call resolution. |

---

## 5. Self-hosted bootstrap: narrow binders

After the large `initialize` (explicit init of hundreds of `@` fields) come **small** methods for stage2 (see comment ~3206):

| Lines | Method | Purpose |
|-------|--------|---------|
| 3209–3215 | `bootstrap_bind_core_state` | `@arena`, `@module`. |
| 3217–3225 | `bootstrap_bind_source_maps` | `@sources_by_arena`, `@paths_by_arena`, reset line counts / extra sources. |
| 3227–3233 | `bootstrap_bind_main_arenas` | `@main_arenas` (copy of arena array). |
| 3235–3237 | `bootstrap_bind_link_libraries` | `@link_libraries`. |
| 3239+ | `bootstrap_reset_constructor_tail` | Reset fields tied to constructor “tail” (splats, literals, defer queues, etc.). |

**Link to `cli.cr`:** these run after a **narrow** `AstToHir.new` to work around miscompilation of the wide constructor in self-hosted builds.

---

## 6. `AstToHir` method statistics (only `def` at 4 spaces, line ≥ 325)

| Metric | Value |
|--------|-------|
| Direct methods on `AstToHir` (not nested struct methods) | **1256** |
| Names matching `lower_*` | **155** |
| Prefix clusters (first token after `lower_`) | see §7 |

**Largest name-prefix buckets (overlapping, heuristic):** `resolve_*` (~69), `register_*` (~46), `infer_*` (~36), `macro_*` (~35), `enum_*` (~18), `class_*` (~15), `def_*` (~15), `parse_*` (~14), `with_*` (~12), `lookup_*` (~11), `union_*` (~7), `emit_*` (~10); remainder `_other` (~609) from automatic prefix bucketing.

---

## 7. `lower_*` index (first-hit anchors by group)

Counts of methods whose name starts with `lower_<token>_` (first token after `lower_`):

| Group | ~count | First line (approx.) | Example name |
|-------|--------|------------------------|--------------|
| `lower_array_*` | 23 | ~62321 | `lower_array_each_intrinsic` |
| `lower_primitive_*` | 13 | ~24301 | `lower_primitive_call` |
| `lower_macro_*` | 8 | ~18020 | `lower_macro_call_in_module_body` |
| `lower_module_*` | 6 | ~11830 | `lower_module_instance_methods_for` |
| `lower_string_*` | 5 | ~24431 | `lower_string_to_unsigned_conversion` |
| `lower_class_*` | 4 | ~20737 | `lower_class` |
| `lower_block_*` | 4 | ~70546 | `lower_block` |
| `lower_expanded_*` | 3 | ~6895 | `lower_expanded_macro_result` |
| `lower_hash_*` | 3 | ~62898 | `lower_hash_each_dynamic` |
| `lower_enum_*` | 3 | ~67443 | `lower_enum_predicate` |
| `lower_method` | 1 | ~22530 | main method lowering entry |
| `lower_def` | 1 | ~36412 | lowering `def` |
| `lower_expr` | 1 | ~37946 | expression dispatcher |
| `lower_virtual_*` | 1 | ~4027 | `lower_virtual_targets_for_child` |
| … | … | … | literals near file end: `lower_hash_literal` ~71788, `lower_as` ~71939, `lower_body` ~72103 |

**Rough top-to-bottom pass (by line):** virtual targets → expanded macros → modules → classes → `lower_method` / primitives → main expr flow → blocks/proc → literals/hashes/tuples → nil/not_nil intrinsics at tail (~74559+).

---

## 8. “V2 safety” / self-hosted patterns

Useful searches in the file:

- **`V2 safety`**, **`self-hosted`**, **`stage2`** — comments for compiler workarounds.
- **`v2_string_readable?`** — checks that `String` bytes are readable (null pointer, address).
- **`NamedTuple`** — explicit avoidance in favor of `struct` + manual `[]` where noted.
- **`@[AlwaysInline]`** on hot `parse_method_name*` / strip paths.
- **`LibMachVM` / `readable_address?`** — guard invalid pointer reads (darwin).

---

## 9. Environment variables (overview)

- Unique **`ADAMAS_*`**: **22** (see `rg -o 'ADAMAS_[A-Z0-9_]+' ast_to_hir.cr | sort -u`).
- Unique **`DEBUG_*`**: **372** — fine-grained debugging; full list only via `rg`, not duplicated here.

Examples of `ADAMAS_*`: `ADAMAS_TRACE_SHOVEL_TYPES`, `ADAMAS_DUMP_LAYOUTS`, `ADAMAS_LAZY_RTA`, `ADAMAS_MISSING_TRACE`, `ADAMAS_TRY_INLINE_MAX`, …

---

## 10. `rg` recipes for this file

```bash
# All direct AstToHir methods (4 spaces before def, from class start)
rg -n '^    (private |protected )?def ' ast_to_hir.cr | awk -F: '$1>=325'

# All lower_* with line numbers
rg -n '^    (private |protected )?def lower_' ast_to_hir.cr

# Method name parsing
rg -n 'parse_method_name|MethodNameParts' ast_to_hir.cr

# Bootstrap
rg -n 'bootstrap_bind|bootstrap_reset' ast_to_hir.cr

# Enum-related lowering
rg -n 'enum_value|enum_tracked|@enum_value_types' ast_to_hir.cr
```

---

## 11. Related documents

- `docs/codegen_architecture.md` (if present) — HIR specification.
- `LANDMARKS.md` — verified bootstrap notes (main clone of the project).

---

## 12. Index limitations

- Does not list **nested** `def` inside `private struct` (6+ spaces) — hundreds of them; inspect locally when editing structs.
- Line numbers **move** on any insert above — recompute with §10.
- Per-method semantics require reading bodies; this file is a **map**, not a spec.
