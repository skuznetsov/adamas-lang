# Plan: Demand-Driven Architecture Rewrite (Variant C) — v2

> Revised after GPT review. All 6 P1/P2 comments incorporated.

## Why This Rewrite

V2 compiles with a **supply-driven** architecture where `ast_to_hir.cr` (77K lines)
merges type inference, method resolution, generic instantiation, and HIR emission
into a single pass. This causes:

1. **Queue explosion** in stage2 builds (130 → 27,000+ functions)
2. **No def_instances cache** — repeated body analysis for the same {method, arg_types}
3. **23% regression** in test compile times (8.9s → 11.0s from accumulated fixes)

The target: **demand-driven** architecture matching original Crystal, with
separate semantic and codegen phases, def_instances caching, and type side tables.

### Re-scoping (GPT P1 #1)

Stage2 release builds can now finish (runtime correctness is the active frontier).
This rewrite is a **strategic architecture track**, not an immediate stage3 unblocker.
The motivation is:
- Eliminating the supply-driven queue explosion pattern permanently
- Reducing codebase from 77K merged lines to ~30K properly separated
- Enabling proper def_instances caching (impossible with current architecture)
- Fixing the +23% compile time regression structurally

## Current V2 Inventory

### Compile path (cli.cr:1287+)
```
Parse → AstToHir (77K, merged everything) → HIR → MIR → LLVM
```

### Check path (cli.cr:1054+)
```
Parse → Analyzer → SymbolCollector → resolve_names → infer_types
```

### Existing semantic stack (already in V2!)
| File | Lines | Purpose |
|------|-------|---------|
| `semantic/analyzer.cr` | 65 | Entry point for check path |
| `semantic/type_inference_engine.cr` | 5,363 | Type inference (check-only) |
| `semantic/collectors/symbol_collector.cr` | ~1,300 | Symbol collection |
| `semantic/types/type_context.cr` | ~130 | ExprId → Type side table |
| `semantic/types/type_index.cr` | ~700 | Type lookup by name |
| `semantic/types/*.cr` | ~2,500 | Type model (class, enum, union, etc.) |
| `semantic/symbol_table.cr` | 95 | Symbol storage |
| `semantic/macro_expander.cr` | 2,658 | Macro expansion |

### AstToHir responsibilities beyond type inference
- Lib/enum/alias/macro registration (cli.cr:1310-1602)
- Method effect summaries for EA/taint (ast_to_hir.cr:3657+)
- C struct size computation and alignment (align_all_class_ivars)
- Module includer tracking
- Extern function/global tables
- Class hierarchy data
- Generic template registration

### Downstream contracts (HIR → MIR → LLVM)
- `hir.cr:1383+` — MethodEffectSummary used by hir_to_mir
- `hir_to_mir.cr:1841+` — escape analysis, lifetime tagging
- `escape_analysis.cr:193+` — uses HIR metadata

## Design Decisions

### Types stay in side tables, NOT on AST nodes (GPT P1 #4)
- AST is arena-backed union (`ast.cr:2299+`)
- Types already live as `ExprId → Type` in `type_context.cr:20+`
- Semantic state stays external to raw AST
- HIR builder reads from type side tables at the boundary

### def_instances keyed by semantic identity, NOT mangled names (GPT P2 #1)
```crystal
# Correct — semantic identity:
record DefInstanceKey,
  def_id : UInt64,        # object identity of the Def AST node
  arg_types : Array(TypeRef),
  block_type : TypeRef?,
  named_arg_types : Array({String, TypeRef})?

# Wrong — stringly typed:
# key = "Array(Int32)#map$$Block" ← collisions, fragmentation
```

### Grow existing semantic stack, don't start from scratch (GPT P1 #2)
- Extend `Analyzer` + `TypeInferenceEngine` into compile path
- Bridge: make AstToHir delegate to semantic stack for type queries
- Eventually: AstToHir becomes pure HIR builder (no type inference)

## Phase Plan

### Phase 0: Inventory + Contracts + Migration Bridge
**Goal**: Understand what AstToHir does, document contracts, create bridge.

Tasks:
- [ ] Inventory ALL responsibilities of AstToHir (beyond type inference)
- [ ] Document HIR output contracts: what metadata MIR/LLVM backend needs
  - Method effect summaries, lifetimes, taints, class hierarchy
  - Extern tables, lib structs, enum info
  - Generic template data
- [ ] Create feature flag: `ADAMAS_SEMANTIC_COMPILE=1`
  - When off: current AstToHir pipeline (default)
  - When on: new semantic → HIR builder pipeline
- [ ] Bridge: make AstToHir queryable for type info from semantic stack
  - Add `TypeContext` side table to AstToHir
  - Gradually move type queries from inline to side table

Deliverable: Contract document + feature flag infrastructure

### Phase 1: Full Declaration Fixed Point (GPT P1 #3)
**Goal**: Complete top-level registration, not just classes/methods.

Extend existing `SymbolCollector` + `Analyzer` to handle ALL declarations:
- [ ] Classes, modules, structs (already in SymbolCollector)
- [ ] Enums with constant evaluation
- [ ] Libs and C struct sizes
- [ ] Aliases and type alias chains
- [ ] Macros (already in macro_expander.cr)
- [ ] Method signatures (params + return type annotations)
- [ ] Module includers/extenders
- [ ] Generic type parameters
- [ ] Method effect annotations (@[NoEscape], @[Acyclic], etc.)

Result: `TypeRegistry` with ALL declared types, equivalent to original Crystal's
`TopLevelVisitor` output. Full fixed point — no ad hoc discovery later.

### Phase 2: Demand-Driven Type Walker + DefInstanceKey
**Goal**: Type-check method bodies on demand with caching.

Implement in `semantic/type_walker.cr`:
- [ ] Visitor pattern on V2's AST nodes (83 visit methods, like original MainVisitor)
- [ ] Visit top-level expressions → trigger call resolution on demand
- [ ] `CallResolver` with `DefInstanceKey` cache:
  ```crystal
  class CallResolver
    @def_instances : Hash(DefInstanceKey, TypedDef) = {}

    def resolve_call(call, scope, arg_types) : TypedDef
      key = DefInstanceKey.new(call.target_def_id, arg_types, block_type)
      if cached = @def_instances[key]?
        return cached  # NO re-inference!
      end
      typed_def = instantiate_and_type_check(call, scope, arg_types)
      @def_instances[key] = typed_def
      typed_def
    end
  end
  ```
- [ ] Type propagation via side tables (`TypeContext`)
- [ ] Union type widening through binding mechanism
- [ ] Generic instantiation on demand (not pre-registered)

Types stored in `TypeContext` side table, NOT on AST nodes.

### Phase 3: HIR Builder (compatible with existing contracts)
**Goal**: Generate HIR from typed AST, preserving ALL downstream contracts.

This is NOT "just a simpler emitter" (GPT P1 #5). Must produce:
- [ ] HIR instructions (current format, compatible with hir_to_mir.cr)
- [ ] Method effect summaries (for escape analysis)
- [ ] Lifetime/taint annotations
- [ ] Class hierarchy data
- [ ] Module includer tables
- [ ] Extern function/global tables
- [ ] Generic template data for MIR

Bridge: initially delegates to AstToHir for complex cases, gradually takes over.

### Phase 4: Pipeline Switch + Rollout
**Goal**: Replace AstToHir in compile path.

- [ ] Shadow mode: run both pipelines, compare HIR output
- [ ] Regression tests pass with new pipeline
- [ ] Feature flag rollout: `ADAMAS_SEMANTIC_COMPILE=1` default
- [ ] Remove AstToHir from compile path
- [ ] Unify check + compile semantic paths

### Phase 5: Cleanup + Performance
- [ ] Remove dead code from AstToHir
- [ ] Stage2 + Stage3 bootstrap verification
- [ ] Performance benchmarks (compile time, memory, binary quality)
- [ ] ARC ownership transfer (now possible with proper semantic info)

## Success Metrics (behavior, not LOC)

| Metric | Current | Target |
|--------|---------|--------|
| Forced lowers per stage2 build | thousands | 0 (demand-driven) |
| Safety-net passes needed | 2+ | 0 |
| Duplicate body analysis | rampant | 0 (def_instances) |
| Queue growth (stage2) | 130→27000+ | N/A (no queue) |
| Test compile time (debug) | 11.0s | <5s |
| Stage2 build | hangs/slow | <60s |
| Regression test score | 87/88 + 18/20 | same or better |

## Risks + Mitigations

1. **Two semantic systems during migration**
   → Feature flag + shadow mode. Check path already uses semantic stack.

2. **HIR contract breakage**
   → Phase 3 explicitly preserves ALL downstream contracts. Shadow comparison.

3. **Self-hosted bootstrap fragility**
   → Never switch default until shadow mode shows identical HIR output.

4. **ARC integration**
   → Lifetime/escape annotations must flow from semantic → HIR → MIR.
   Preserve existing effect summary mechanism.

5. **Block/closure/proc complexity**
   → Port incrementally. Original Crystal's block handling is well-understood.

## Reference Files

### Original Crystal (to study/port from)
- `semantic/main_visitor.cr` (3667 lines) — demand-driven type inference
- `semantic/call.cr` (1272 lines) — method resolution + def_instances
- `semantic/bindings.cr` (958 lines) — type propagation
- `semantic/method_lookup.cr` (551 lines) — method matching
- `types.cr` (3601 lines) — type system + DefInstanceContainer
- `codegen/codegen.cr` (2629 lines) — LLVM codegen visitor

### V2 existing semantic stack (to extend)
- `semantic/analyzer.cr` (65 lines) — entry point, extend for compile
- `semantic/type_inference_engine.cr` (5363 lines) — type inference, extend
- `semantic/collectors/symbol_collector.cr` (~1300 lines) — extend for full declarations
- `semantic/types/type_context.cr` (130 lines) — ExprId → Type side table
- `semantic/types/type_index.cr` (700 lines) — type lookup

### V2 to keep/adapt
- `frontend/parser.cr` (16K) — KEEP
- `mir/hir_to_mir.cr` (5.7K) — ADAPT inputs
- `mir/llvm_backend.cr` (20K) — ADAPT inputs
- `hir/hir.cr` — EXTEND metadata
- `mir/optimizations.cr` — KEEP
