# Phase 0: HIR Contract Inventory + Legacy Metrics

## 1. HIR Module Contract (consumed by MIR + LLVM)

The `HIR::Module` is the output of `AstToHir` and the input to `HIRToMIRLowering`
and (indirectly via MIR) `LLVMIRGenerator`.

### 1.1 Core data

| Field | Type | Consumed by | Purpose |
|-------|------|-------------|---------|
| `functions` | `Array(Function)` | MIR (iterate + lower) | All HIR function bodies |
| `types` | `Array(TypeDescriptor)` | MIR (type lookup), LLVM (type emission) | Type metadata: name, kind, size, alignment, fields |
| `extern_functions` | `Array(ExternFunction)` | MIR (extern call lowering), LLVM (declare) | C library function declarations |
| `extern_globals` | `Array(ExternGlobal)` | MIR (global refs), LLVM (global declare) | C library global declarations |
| `strings` | `Array(String)` | MIR/LLVM (string pool) | Interned string constants |
| `link_libraries` | `Array(String)` | CLI (linker flags) | -l flags for linker |

### 1.2 Semantic metadata

| Field | Type | Consumed by | Purpose |
|-------|------|-------------|---------|
| `method_effects` | `Hash(String, MethodEffectSummary)` | MIR (escape analysis, lifetime), LLVM (ARC decisions) | Per-method: no_escape, transfer, thread_shared, ffi_exposed |
| `class_parents` | `Hash(String, String?)` | MIR (vdispatch, class hierarchy), LLVM (type_id dispatch) | Parent class for each class |
| `module_includers` | `Hash(String, Array(String))` | MIR (method resolution, RTA), LLVM (vdispatch) | Which classes include which modules |
| `lib_names` | `Set(String)` | MIR/LLVM (C struct detection) | Names of lib modules |
| `lib_structs` | `Set(String)` | MIR (field_storage_size), LLVM (inline vs ptr) | C struct names (inlined, not heap-allocated) |
| `primitive_methods` | `Hash(String, String)` | LLVM (hardcoded primitives) | Method → primitive kind mapping |

### 1.3 Type descriptors (in `types` array)

Each `TypeDescriptor` contains:
- `name : String` — qualified type name
- `kind : TypeKind` — Primitive, Class, Struct, Module, Union, Tuple, NamedTuple, Proc, Array, Hash, Pointer, Generic
- `type_ref : TypeRef` — internal type ID
- `size : Int32` — byte size (0 if unknown)
- `alignment : Int32`
- `type_params : Array(TypeRef)` — for unions: variant type refs
- `element_type : TypeRef?` — for arrays/pointers

### 1.4 Functions

Each `HIR::Function` contains:
- `name : String` — mangled function name
- `params : Array(Parameter)` — typed parameters
- `return_type : TypeRef`
- `blocks : Array(Block)` — basic blocks with instructions
- `entry_block : BlockId`
- Scopes for variable tracking

### 1.5 Additional data from AstToHir (NOT in HIR::Module)

These are passed separately through CLI orchestration:

| Data | Source | Destination | Purpose |
|------|--------|-------------|---------|
| `class_info` | AstToHir | CLI → MIR (globals, allocators) | Per-class: ivars, size, is_struct, parent |
| `constant_literal_values` | AstToHir | CLI → LLVM (const init) | Compile-time constant values |
| `union_descriptors` | AstToHir | MIR + LLVM (union layout) | Union variant metadata |
| `acyclic_types` | CLI scan | MIR (memory strategy) | @[Acyclic] annotated types |
| `top_level_type_names` | CLI scan | AstToHir (resolution) | Top-level type name set |

## 2. Legacy Supply-Driven Metrics

### 2.1 Metrics to instrument

| Metric | Where | What to measure |
|--------|-------|-----------------|
| `forced_lower_count` | `force_lower_function_for_return_type` | How many times body is analyzed just to get return type |
| `forced_lower_unique` | same | Unique function names force-lowered |
| `pending_queue_max` | `process_pending_lower_functions` | Peak queue size during worklist processing |
| `pending_queue_growth` | same | Queue size at each pass start |
| `safety_net_passes` | `emit_all_tracked_signatures` | Number of safety-net signature emission rounds |
| `safety_net_functions` | same | Functions emitted by safety net |
| `duplicate_body_analysis` | `lower_function_if_needed_impl` | How many times same function name is lowered (>1 = duplicate) |
| `total_functions_lowered` | worklist | Total functions processed across all passes |
| `total_functions_emitted` | HIR module | Final function count in output |
| `rta_deferred_total` | RTA | Functions deferred by lazy RTA |

### 2.2 Where to add instrumentation

```crystal
# In ast_to_hir.cr:
@phase0_forced_lower_count = 0
@phase0_forced_lower_names = Set(String).new
@phase0_pending_queue_max = 0
@phase0_duplicate_body_count = 0
@phase0_safety_net_passes = 0
@phase0_lower_name_counts = Hash(String, Int32).new(0)

# At end of compilation, dump metrics:
def dump_phase0_metrics(io : IO)
  io.puts "[PHASE0] forced_lowers=#{@phase0_forced_lower_count} unique=#{@phase0_forced_lower_names.size}"
  io.puts "[PHASE0] queue_max=#{@phase0_pending_queue_max}"
  io.puts "[PHASE0] safety_net_passes=#{@phase0_safety_net_passes}"
  io.puts "[PHASE0] duplicates=#{@phase0_duplicate_body_count}"
  io.puts "[PHASE0] total_functions=#{@module.function_count}"
end
```

## 3. SemanticTypeId Design

### 3.1 Requirements

- Must be canonical: same type always gets same id
- Must NOT be a mangled string name
- Must NOT be an HIR TypeRef (those are assigned incrementally)
- Must be stable across emission order changes
- Must have adapter to HIR TypeRef (one-way, at emission boundary)

### 3.2 Proposed design

```crystal
# Canonical semantic type identity
struct SemanticTypeId
  # For primitive types: use a fixed enum
  # For user types: use qualified name hash + kind
  # For generic instantiations: combine base + arg type ids

  getter value : UInt64

  # Constructors for each category
  def self.primitive(kind : PrimitiveKind) : self
    new(kind.value.to_u64)
  end

  def self.named(qualified_name : String, kind : TypeKind) : self
    # Stable hash of qualified name + kind
    h = qualified_name.hash.to_u64
    h = h ^ (kind.value.to_u64 << 56)
    new(h)
  end

  def self.generic(base : SemanticTypeId, args : Array(SemanticTypeId)) : self
    h = base.value
    args.each { |a| h = h ^ (a.value &* 0x9e3779b97f4a7c15_u64) }
    new(h)
  end

  def self.union(variants : Array(SemanticTypeId)) : self
    sorted = variants.map(&.value).sort
    h = 0_u64
    sorted.each { |v| h = h ^ (v &* 0x517cc1b727220a95_u64) }
    new(h | (1_u64 << 63))  # high bit = union marker
  end
end

# Adapter: SemanticTypeId → HIR TypeRef
class SemanticToHIRAdapter
  @mapping : Hash(SemanticTypeId, HIR::TypeRef) = {}

  def resolve(semantic_id : SemanticTypeId) : HIR::TypeRef
    @mapping[semantic_id]? || register(semantic_id)
  end

  private def register(semantic_id : SemanticTypeId) : HIR::TypeRef
    # Allocate new HIR TypeRef and map
    type_ref = @hir_module.next_type_ref
    @mapping[semantic_id] = type_ref
    type_ref
  end
end
```

### 3.3 DefInstanceKey design

```crystal
record DefInstanceKey,
  # Identity of the method definition (stable across compilations)
  def_qualified_name : String,  # e.g., "Array(T)#map"
  # Semantic types of arguments at this call site
  receiver_type : SemanticTypeId?,
  arg_types : Array(SemanticTypeId),
  block_type : SemanticTypeId?,
  named_arg_types : Array({String, SemanticTypeId})?
```

Note: `def_qualified_name` is the UNmangled method name (not arg-type-suffixed).
The arg types are in `arg_types` as semantic ids. This avoids stringly-typed keys.

## 4. Compile-Path Integration Design

### 4.1 Current check path flow

```
Parser → AstArena (single program) → Analyzer → SymbolCollector → resolve → infer
```

### 4.2 Current compile path flow

```
Parser → multiple AstArenas (prelude + requires) → AstToHir (aggregates all arenas)
```

### 4.3 Gap: multi-file aggregation

`TypeInferenceEngine` assumes single `AstArena`. Compile path has:
- Multiple arenas (one per parsed unit)
- Source maps: `sources_by_arena`, `paths_by_arena`
- Main arenas ordered list
- Macro-expanded arenas

### 4.4 Required changes for compile-path integration

1. **Multi-arena support in Analyzer/TypeInferenceEngine**
   - Accept `Array(ParsedUnit)` instead of single `Program`
   - Iterate arenas in dependency order
   - Symbol collection across arenas

2. **Prelude handling**
   - Prelude parsed first, then user files
   - stdlib types must be available before user code analysis
   - Macro expansion may add new arenas

3. **Source provenance**
   - Each type/function retains source file + line + column
   - Diagnostics reference correct file
   - HIR emission preserves provenance for debug info

4. **Arena-aware type resolution**
   - Type names resolved in correct arena context
   - Nested types scoped to their defining arena
   - Cross-arena references through qualified names

## 5. Normalized Shadow Comparator Spec

### 5.1 What to normalize

- Function IDs → normalized by stable function name ordering
- Value IDs → renumber sequentially per function
- Block IDs → renumber sequentially per function
- Type IDs → map to canonical SemanticTypeId, then compare

### 5.2 What to compare

| Aspect | Comparison method |
|--------|------------------|
| Function set | Compare by name + param types + return type |
| Instruction stream | After ID normalization, instruction-by-instruction |
| Call targets | Normalized callee name |
| Type descriptors | By name + kind + params after normalization |
| Method effects | By function name + effect flags |
| Class hierarchy | By name + parent name |
| Module includers | By name + includer set |
| Extern tables | By name + types |
| Union descriptors | By name + variant set (order-independent) |

### 5.3 Green conditions

A shadow run is green when:
1. Normalized HIR comparison shows no semantic differences
2. MIR generation succeeds on new HIR
3. LLVM generation succeeds on new MIR
4. Runtime smoke tests pass (hello world, tree benchmark, regression subset)

## 6. Feature Flag Skeleton

```crystal
# In bootstrap_shims.cr or cli.cr:
module CrystalV2::Compiler
  SEMANTIC_COMPILE = BootstrapEnv.enabled?("CRYSTAL_V2_SEMANTIC_COMPILE")
  SEMANTIC_SHADOW  = BootstrapEnv.enabled?("CRYSTAL_V2_SEMANTIC_SHADOW")
  SEMANTIC_ASSERT_NO_LEGACY = BootstrapEnv.enabled?("CRYSTAL_V2_SEMANTIC_ASSERT_NO_LEGACY_QUEUE")
end

# Kill-switch assertions (add to legacy paths):
private def assert_no_legacy_queue!
  if CrystalV2::Compiler::SEMANTIC_ASSERT_NO_LEGACY
    raise "KILL-SWITCH: legacy queue machinery invoked under semantic compile flag"
  end
end
```

## 7. Exit Criteria for Phase 0

- [ ] This contract document exists and is reviewed
- [ ] Legacy-path metrics are instrumentable (counters defined, insertion points identified)
- [ ] Normalized comparison format is specified (this document section 5)
- [ ] SemanticTypeId design is reviewed and approved
- [ ] Compile-path integration gaps are documented (this document section 4)
- [ ] Feature flag skeleton is defined
- [ ] Kill-switch assertion points are identified
