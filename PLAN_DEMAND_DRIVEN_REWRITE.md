# Plan: Demand-Driven Architecture Rewrite (Variant C)

## Executive Summary

V2's current architecture merges type inference and codegen into a single
supply-driven pass (`ast_to_hir.cr`, 77K lines). This causes:
- **Worklist explosion**: 130 → 27,000+ pending functions
- **No def_instances cache**: repeated body analysis for same method
- **Stage3 blocker**: build hangs in process_pending_lower_functions

The fix: rewrite to match original Crystal's **demand-driven** architecture
with separate semantic (type inference) and codegen passes.

## Current Architecture (V2 — broken)

```
Parse → AstToHir (77K lines, merged semantic+codegen) → MIR → LLVM

Problems:
1. Supply-driven: register ALL methods, filter via RTA
2. No def_instances cache
3. force_lower_function_for_return_type re-analyzes bodies
4. Generic instantiation explosion (130 → 27000+ queue)
```

## Target Architecture (Original Crystal — proven)

```
Parse → TopLevelVisitor → MainVisitor(semantic) → CodeGenVisitor → LLVM

Key properties:
1. Demand-driven: only type-check methods that are called
2. def_instances cache: {def_id, arg_types, block_type} → typed_def
3. Type bindings: AST nodes observe type changes, propagate
4. CleanupTransformer: dead code elimination before codegen
```

## Original Crystal Architecture Deep Dive

### Phase 1: TopLevelVisitor (declarations only)
- File: `semantic/top_level_visitor.cr` (1352 lines)
- Registers: classes, modules, structs, enums, lib, macros, defs (signatures only)
- Does NOT type-check method bodies
- Does NOT instantiate generics
- Result: `Program` with all types and untyped method signatures

### Phase 2: MainVisitor (demand-driven type inference)
- File: `semantic/main_visitor.cr` (3667 lines)
- Entry: `node.accept(visitor)` on the full program AST
- Visits top-level expressions → triggers call resolution
- Call resolution (`semantic/call.cr`, 1272 lines):
  1. `Call#recalculate` → `lookup_matches` → find matching `Def`
  2. Check `def_instances` cache (key = {def.object_id, arg_types, block_type})
  3. Cache HIT → return immediately (NO body analysis)
  4. Cache MISS → instantiate typed_def, cache it, visit body recursively
- Each method body is analyzed EXACTLY ONCE per unique {def, arg_types}
- Type propagation via `bindings.cr`: nodes observe + propagate type changes
- Union types widen naturally through binding mechanism

### Phase 3: CleanupTransformer
- File: `semantic/cleanup_transformer.cr` (1183 lines)
- Removes dead code, simplifies type casts
- Runs AFTER all types are inferred

### Phase 4: CodeGenVisitor (LLVM IR generation)
- File: `codegen/codegen.cr` (2629 lines) + `codegen/call.cr` (634 lines)
- Visits TYPED AST (every node has `.type`)
- `target_def_fun` cache: mangled_name → LLVM function
- Method body codegen is also demand-driven and cached
- Struct types computed by `LLVMTyper` (612 lines)

### def_instances: The Critical Cache
```crystal
# In types.cr:
module DefInstanceContainer
  getter(def_instances) { {} of DefInstanceKey => Def }

  def add_def_instance(key, typed_def)
    def_instances[key] = typed_def
  end

  def lookup_def_instance(key)
    def_instances[key]?
  end
end

# Key = {def_object_id, arg_types, block_type, named_args_types}
# This prevents Array(Int32)#map from being re-analyzed 50 times
# when called from 50 different places.
```

## Rewrite Plan

### What to KEEP from V2
- **Parser** (`frontend/parser.cr`, 16K lines): works perfectly, identical syntax
- **Lexer** (`frontend/lexer.cr`): works perfectly
- **AST nodes** (`frontend/ast.cr`): works
- **MIR** (`mir/mir.cr`): instruction set, keep but adapt input
- **HIR→MIR** (`mir/hir_to_mir.cr`, 5.7K lines): keep, adapt to new HIR format
- **LLVM backend** (`mir/llvm_backend.cr`, 20K lines): keep, adapt to new MIR
- **ARC/RC system**: keep, works correctly
- **Regression tests**: keep all 87+20

### What to REWRITE
- **ast_to_hir.cr** (77K lines) → split into:
  1. `semantic/type_walker.cr` — demand-driven type inference (~5-8K lines)
  2. `semantic/call_resolver.cr` — method lookup + def_instances (~2-3K lines)
  3. `semantic/type_registry.cr` — type declarations, class info (~3-5K lines)
  4. `hir/hir_builder.cr` — HIR generation from typed AST (~10-15K lines)

  Total: ~20-30K lines replacing 77K lines

### What to ADAPT
- **HIR** (`hir/hir.cr`): extend with type information from semantic pass
- **CLI** (`cli.cr`): update pipeline to new phases

## Phase Plan

### Phase 1: Type Registry (foundation)
- Port `TopLevelVisitor` logic from ast_to_hir's registration code
- Class/module/struct/enum/lib declarations
- Method signatures (without body analysis)
- Generic type parameters
- Result: `TypeRegistry` with all declared types

### Phase 2: Demand-Driven Type Walker
- Implement visitor pattern on V2's AST nodes
- Visit top-level expressions → trigger call resolution
- Implement `def_instances` cache
- Call resolution: lookup method → check cache → analyze body if needed
- Type propagation: each AST node gets `.type` field
- Key methods to port from original Crystal:
  - `Call#recalculate` → `Call#lookup_matches` → `def_instances` lookup
  - `MainVisitor#visit(Call)` → method instantiation
  - Type widening (union creation) via binding mechanism

### Phase 3: HIR Builder
- Walk typed AST → generate HIR instructions
- Similar to current ast_to_hir but WITHOUT type inference logic
- All types already resolved → just emit operations
- Much simpler than current 77K lines

### Phase 4: Adapt MIR + LLVM Backend
- HIR format may change slightly (typed nodes)
- HIR→MIR adapter for new HIR format
- LLVM backend should need minimal changes

### Phase 5: Integration + Testing
- Wire new pipeline into CLI
- Regression tests must pass
- Stage2 + Stage3 bootstrap test
- Performance benchmarks

## Key Metrics for Success

| Metric | Current V2 | Target | Original Crystal |
|--------|-----------|--------|-----------------|
| Queue size (stage2 build) | 130→27000+ | 130→~3000 | N/A (demand-driven) |
| Hello world functions | ~3130 | ~2300 | ~2300 |
| Single test compile time | 11.0s (debug) | <5s (debug) | ~3s |
| Stage2 build time | hangs | <60s | N/A |
| Total codegen source lines | 77K+5.7K+20K=103K | ~30K+5.7K+20K=56K | 24K+11K=35K |

## Risks

1. **ARC integration**: New semantic pass must annotate lifetime/escape info for ARC
2. **V2-specific features**: Some V2 additions (slab allocator, ARC, MIR optimizations)
   need to be preserved in the new architecture
3. **Block/closure/proc**: Original Crystal's block handling is complex
4. **Macro expansion**: V2 has its own macro system; needs to work with new semantic

## For GPT Review

Questions for GPT to verify:
1. Is the Phase plan ordering correct? Any dependencies missed?
2. Are there parts of ast_to_hir.cr that DON'T fit into either semantic or codegen?
3. What's the right granularity for def_instances key in V2?
   (V2 uses string-mangled names vs original Crystal's object_id)
4. How should generic instantiation work with demand-driven?
   Original Crystal instantiates on-demand. V2 currently pre-registers.
5. What about the safety nets (emit_all_tracked_signatures)?
   Should be unnecessary with demand-driven but may need transition period.

## Reference Files

### Original Crystal (to study/port from)
- `crystal/src/compiler/crystal/semantic/main_visitor.cr` (3667 lines) — core type inference
- `crystal/src/compiler/crystal/semantic/call.cr` (1272 lines) — method resolution + def_instances
- `crystal/src/compiler/crystal/semantic/bindings.cr` (958 lines) — type propagation
- `crystal/src/compiler/crystal/semantic/method_lookup.cr` (551 lines) — method matching
- `crystal/src/compiler/crystal/types.cr` (3601 lines) — type system + DefInstanceContainer
- `crystal/src/compiler/crystal/codegen/codegen.cr` (2629 lines) — LLVM codegen visitor
- `crystal/src/compiler/crystal/codegen/call.cr` (634 lines) — call codegen
- `crystal/src/compiler/crystal/codegen/fun.cr` (658 lines) — function codegen + cache

### V2 (to keep/adapt)
- `crystal_v2_repo/src/compiler/frontend/parser.cr` — KEEP (16K, perfect)
- `crystal_v2_repo/src/compiler/mir/hir_to_mir.cr` — ADAPT (5.7K)
- `crystal_v2_repo/src/compiler/mir/llvm_backend.cr` — ADAPT (20K)
- `crystal_v2_repo/src/compiler/hir/hir.cr` — EXTEND with types
- `crystal_v2_repo/src/compiler/mir/mir.cr` — KEEP
- `crystal_v2_repo/src/compiler/mir/optimizations.cr` — KEEP
