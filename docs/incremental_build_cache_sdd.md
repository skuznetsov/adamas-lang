# Incremental Build Cache Frontier SDD

Document status: PROPOSED, design-only, rehabilitation-first. This document
does not enable any cache, change defaults, or approve a behavior flip.

Current frontier: Adamas already has several cache layers, but they are split
between the compiler CLI and LSP paths, and some compiler-path reads are
disabled because previous bootstrap/runtime bugs made them unsafe. The desired
direction is to reuse the existing work, not design a second cache stack from
scratch.

Bounded context:

- compiler CLI cache surfaces in `src/compiler/cli.cr`,
- LSP cache surfaces in `src/compiler/lsp/ast_cache.cr`,
  `src/compiler/lsp/project_cache.cr`, `src/compiler/lsp/prelude_cache.cr`,
  and `src/compiler/lsp/semantic_token_cache.cr`,
- future compiler architecture boundaries in
  `docs/compiler_architecture_sdd.md`.

ProblemCardRef: recompiling everything after one small source change is too
slow. The cache should stay bounded in size, reuse already-computed safe
artifacts, and never preserve a stale semantic decision or bootstrap bug as a
cache hit.

## 1. Existing cache inventory

This table is a live map of cache surfaces that already exist. Re-verify before
implementation because some entries are intentionally disabled or gated.

| Layer | Current owner | Current default | Artifact | Current risk / note |
|-------|---------------|-----------------|----------|---------------------|
| LLVM tail cache | `CLI#compile_llvm_ir` in `src/compiler/cli.cr` | enabled unless `ADAMAS_LLVM_CACHE=0` or `--no-llvm-cache` | optimized bitcode and object files keyed by `.ll` hash plus opt/llc tags | Useful tail cache, not an incremental semantic build cache. |
| Pipeline `.ll` cache | `src/compiler/cli.cr` pipeline cache path | disabled | whole-module `.ll` plus link libs keyed by all loaded source contents and compile options | Coarse exact-build cache; one changed file misses the whole cache. Disabled due bootstrap File/Dir runtime risk. |
| Compiler-path AST cache read | `parse_file_recursive` in `src/compiler/cli.cr` | disabled by `if false && options.ast_cache`; option also defaults false | serialized AST arena and roots, plus require cache | Disabled because AST roundtrip loses data in compiler path and previous bootstrap File/String bugs made reads unsafe. |
| LSP AST cache | `src/compiler/lsp/ast_cache.cr` | LSP-only | binary AST with compiler fingerprint and source mtime-ns | Existing implementation can be reused only through compiler-grade parity gates. |
| LSP project cache | `src/compiler/lsp/project_cache.cr` | LSP-only | per-file symbols, requires, binary summaries, optional `TypeIndex`; max cache size guard | Uses project-root hash and file mtimes; good seed for declaration-summary cache, not enough by itself for compiler builds. |
| LSP prelude cache | `src/compiler/lsp/prelude_cache.cr` | LSP-only | stdlib symbols, cached file states, optional `TypeIndex` | Useful model for prelude summary reuse; compiler path needs stronger certificates. |
| Semantic token cache | `src/compiler/lsp/semantic_token_cache.cr` | LSP-only | user-facing semantic tokens | Keep separate; not a compiler build artifact. |

The existing stack is valuable, but its current identities are LSP-oriented.
Compiler builds need stronger cache certificates because they affect emitted
program behavior and self-host bootstrap.

Disabled cache paths are not automatically dead code. They are
`suspected_dead`, `legacy_shim`, or `rehabilitation_candidate` until a cache
census proves whether they should be promoted, shadow-tested, or deleted. See
`docs/compiler_architecture_sdd.md` for the shared `CodePathStatus` cleanup
contract.

## 2. Admitted surface

This SDD admits cache work that:

- starts with read-only inventory and hit/miss measurement;
- rehabilitates existing caches before adding new large artifact stores;
- separates tail caching, frontend summary caching, semantic/materialization
  caching, and object caching;
- uses content and semantic certificates, not mtime-only trust, for compiler
  build hits;
- fails closed to rebuild when any certificate field is missing, stale, or from
  an unknown schema;
- keeps behavior identical to no-cache builds before any default-on decision;
- keeps cache size bounded and visible.

The first behavior target is declaration/require summary reuse, not full HIR,
MIR, or object reuse.

## 3. Rejected surface

The following are explicitly rejected:

- enabling the currently disabled compiler-path AST read without a roundtrip
  fidelity matrix;
- treating the whole-module pipeline `.ll` cache as incremental build support;
- using LSP mtime-only project cache hits as compiler build hits;
- caching materialized HIR/MIR functions while `CallResolution`,
  `Materialization`, and ABI facts are still implicit and string-keyed;
- relying on `String#hash` or process-randomized keys for persistent artifacts;
- allowing a cache hit to bypass bootstrap crash frontiers that the no-cache
  path still exposes;
- default-on cache changes before `s2b`/`s3b` smoke and no-cache parity;
- deleting disabled cache code before recording why it is disabled and which
  certificate/falsifier would be required to rehabilitate it.

## 4. Guard-only future

Allowed as guard-only work:

- cache census counters for existing layers;
- a cache certificate printed under `--stats` or an env trace;
- dry-run cache lookup that reports would-hit/would-miss without consuming the
  artifact;
- shadow comparison between cached summary and freshly computed summary;
- one-file warm-build harnesses that compare no-cache and cache paths;
- disk-size and entry-age reporting.

Guard-only means no cached artifact may affect compile output.

## 5. Non-goals

- Do not build a distributed cache.
- Do not optimize dependency fetching or package management.
- Do not change stdlib files.
- Do not make incremental compilation depend on LSP server state.
- Do not replace the existing LSP cache stack; wrap or share safe pieces.
- Do not promise object-level incremental linking in the first slice.

## 6. Design laws

1. Cache hit is a proof obligation.
   A hit is admitted only when its certificate proves the artifact was produced
   by a compatible compiler, flags, source set, schema, and semantic boundary.

2. Summaries before bodies.
   Cache declarations, requires, and exported summaries before caching HIR/MIR
   function bodies.

3. Interface hash before implementation hash.
   A body-only edit should not invalidate unrelated declaration summaries.

4. No semantic guessing on read.
   A cache reader may validate certificates and load facts. It must not repair
   missing name, type, layout, or materialization decisions.

5. LSP cache data is suspect until promoted.
   Existing LSP caches are useful seeds, but compiler reuse requires stronger
   parity checks and certificates.

6. Size is a first-class budget.
   Every persistent cache layer must have a max-size policy, an admission rule,
   and a cheap way to inspect bytes used.

7. Bootstrap is an adversary.
   A cache that works for small user programs is not compiler-grade until it
   passes no-cache parity plus bootstrap smoke in the relevant stage.

8. Tail cache is not semantic cache.
   LLVM opt/llc/object reuse can stay independent. It does not prove frontend
   incremental correctness.

## 7. Cache artifact tiers

### Tier 0: Fingerprints and dependency graph

Artifact:

```text
SourceFingerprint {
  path
  content_hash
  size
  mtime_ns
}

RequireGraphSummary {
  file
  direct_requires
  resolved_requires
  has_glob_require
}
```

Purpose:

- know what changed,
- avoid reparsing unchanged dependency graph roots,
- provide stable inputs for higher tiers.

Cache size target: tiny.

Admitted first: yes.

### Tier 1: Declaration summaries

Artifact:

```text
DeclSummary {
  file
  exported_symbols
  classes
  modules
  defs
  macros
  aliases
  constants
  interface_hash
  implementation_hash
}
```

Purpose:

- avoid redoing declaration discovery for unchanged files,
- decide whether downstream semantic work must invalidate.

Cache size target: small.

Admitted first: yes, after census.

### Tier 2: Parsed AST blobs

Artifact:

```text
AstBlob {
  file
  ast_schema_version
  parser_version
  compiler_fingerprint
  source_hash
  arena_payload
  roots
  string_pool
}
```

Purpose:

- avoid parsing large unchanged files.

Cache size target: bounded LRU.

Admitted first: no. The compiler-path AST read is currently disabled, so this
tier needs AST roundtrip falsifiers before use.

### Tier 3: Name/type summaries

Artifact:

```text
SemanticSummary {
  file_or_module
  name_resolution_epoch
  type_identity_epoch
  visible_symbols
  resolved_aliases
  candidate_owner_sets
}
```

Purpose:

- avoid recomputing stable name/type surfaces.

Cache size target: small to medium.

Admitted first: no. This depends on the `NameResolution` and `TypeIdentity`
boundaries from `docs/compiler_architecture_sdd.md`.

### Tier 4: Materialized HIR/MIR functions

Artifact:

```text
FunctionArtifact {
  materialization_key
  call_resolution_key
  abi_contract_version
  hir_or_mir_payload
  dependency_fingerprints
}
```

Purpose:

- avoid re-lowering unchanged function materializations.

Cache size target: admission-controlled LRU.

Admitted first: no. This depends on sealed `CallResolution`,
`Materialization`, and `AbiFacts` boundaries.

### Tier 5: LLVM/object artifacts

Artifact:

```text
LlvmTailArtifact {
  llvm_ir_hash
  opt_tag
  llc_tag
  target_triple
  output_path
}
```

Purpose:

- skip `opt` and `llc` for identical LLVM IR.

Cache size target: bounded by bytes; evict old objects first.

Admitted first: already exists as the LLVM tail cache. Treat it as a separate
tail optimization, not incremental semantic reuse.

## 8. Compiler-grade cache certificate

Every compiler-build cache artifact must be guarded by a certificate. Minimum
fields:

```text
CacheCertificate {
  cache_schema_version
  artifact_kind
  producer_compiler_fingerprint
  source_root
  stdlib_root
  stdlib_fingerprint
  target_triple
  compile_flags
  env_gate_fingerprint
  memory_mode
  source_fingerprints
  require_graph_hash
  interface_hash
  implementation_hash
  architecture_epoch
}
```

`architecture_epoch` is a compact version field bumped when any boundary that
affects the artifact changes:

- parser/AST schema,
- name resolution,
- type identity,
- call resolution,
- materialization,
- ABI/layout facts,
- backend lowering contracts.

If a field is unknown, the hit is rejected.

## 9. Invalidation model

### Local source edit

- content hash changes;
- implementation hash changes;
- interface hash may or may not change.

If only implementation hash changes:

- invalidate affected function bodies and downstream object artifacts;
- preserve declaration summaries and unrelated files.

If interface hash changes:

- invalidate dependents that imported symbols or overload sets from the file.

### Require graph change

- invalidate dependent file ordering and prelude/project summary assumptions;
- rebuild summaries for files whose direct or transitive require set changed.

### Macro change

Macros are cache-hostile until their dependency model is explicit.

Default rule:

- macro body/signature/interface change invalidates consumers that expanded it;
- if expansion provenance is unavailable, fail closed to broader rebuild.

### Type/layout change

Any class/struct layout, ABI fact, or storage context change invalidates:

- dependent type summaries,
- materialized functions that touch the type,
- LLVM/object tail artifacts.

### Compiler or gate change

Any compiler binary/source fingerprint, target, major flag, memory mode, or env
gate change invalidates compiler-grade artifacts unless explicitly proven
irrelevant to that artifact kind.

## 10. Size and admission policy

Cache directory layout should separate layers:

```text
adamas_cache/
  fingerprints/
  decl_summaries/
  ast/
  semantic/
  materialized/
  llvm_tail/
  index.db or manifest
```

Admission rules:

- Tier 0 and Tier 1 are always eligible if certificates are complete.
- Tier 2 is eligible only after AST roundtrip parity passes.
- Tier 3 and Tier 4 require sealed architecture boundaries.
- Tier 5 keeps the existing LLVM tail behavior, but must have a byte cap.

Eviction rules:

- enforce per-layer byte caps;
- evict largest cold artifacts first for Tier 4 and Tier 5;
- keep Tier 0/Tier 1 small enough that eviction rarely matters;
- never evict by deleting a file whose manifest entry is being written; use
  temp files plus atomic rename.

Recommended first limits:

- declaration summaries: 32 MB per project,
- AST blobs: 256 MB per project,
- materialized HIR/MIR: disabled initially,
- LLVM tail: configurable, default capped rather than unbounded.

## 11. Execution order

### Phase 0: Read-only cache census

Collect:

- current cache option defaults;
- hit/miss counters for LLVM tail, pipeline, AST, project/prelude if available;
- cache directory sizes;
- reasons each disabled path is disabled;
- `CodePathStatus` for disabled cache readers/writers:
  `rehabilitation_candidate`, `legacy_shim`, `debug_only`, or `delete_ready`;
- cost attribution for cold build phases.

No behavior changes.

Exit signal:

- `docs/incremental_build_cache_census.md` or SDD section update with measured
  cold/warm times and current cache bytes.

### Phase 1: Cache certificate library

Introduce behavior-neutral certificate generation:

- compiler fingerprint,
- source fingerprints,
- stdlib fingerprint,
- compile flags/gates,
- require graph hash.

No cache reads are admitted yet.

Exit signal:

- no-cache output byte-identical;
- certificate trace is deterministic across repeated builds with unchanged
  inputs.

### Phase 2: Declaration summary cache

Promote or adapt LSP project-cache summary pieces through a compiler-safe
facade.

Behavior:

- cache declarations, symbols, requires, interface hash, implementation hash;
- shadow-compare cached summary against freshly computed summary;
- only after parity, allow summary hits to skip summary recomputation.

Exit signal:

- focused reducers prove body-only edit preserves downstream declaration
  summaries;
- exported signature/class/alias/macro edit invalidates dependents.

### Phase 3: AST read rehabilitation

Revisit compiler-path AST read after parser and file/runtime bootstrap risks are
closed.

Behavior:

- dry-run load and compare parsed roots/required files/spans;
- then env-gated AST read;
- never default-on until bootstrap parity holds.

Exit signal:

- AST-cache and no-cache compile paths emit equivalent HIR/MIR for the falsifier
  matrix;
- no stale arena/source-string references.

### Phase 4: Semantic and materialization caches

Only after `CallResolution`, `NameResolution`, `TypeIdentity`, and
`Materialization` boundaries are sealed.

Behavior:

- cache by typed keys, not mangled strings alone;
- reject hits if any boundary epoch mismatches.

Exit signal:

- split/block/join/phantom-hash falsifiers stay green with cache hits.

### Phase 5: Tail/object cache cleanup

Keep LLVM tail cache separate, but make it operator-safe:

- byte cap,
- stats,
- cache prune command,
- robust target/flags/compiler fingerprint.

Exit signal:

- exact `.ll` hit skips opt/llc;
- source change with identical `.ll` may reuse tail artifact;
- no semantic cache claim is made from tail hits.

## 12. Falsifier roster

Minimum falsifiers before a cache layer can affect compiler output:

- no-cache vs cache HIR/MIR/LLVM parity for a small program;
- body-only edit does not invalidate declaration summaries;
- exported def/class/alias/macro change invalidates dependent summaries;
- glob require and missing require cases reject stale require-cache hits;
- macro expansion provenance change rejects stale summaries;
- AST cache roundtrip preserves roots, spans needed by diagnostics, and require
  discovery;
- no stale arena/source-string references after AST cache load;
- `String#split` overload and block-shape reducers stay green with cache hits;
- phantom builtin-base and hash typeref reducers stay green with cache hits;
- A-prime/C-narrow ABI reducers stay green with cache hits;
- `s2b` smoke runs with cache enabled before any default-on promotion.

## 13. Stop rules

Stop and return to census/design if:

- a cache hit requires reconstructing missing semantic state;
- a cached artifact lacks a complete certificate;
- cache-on output differs from no-cache output before the slice explicitly
  admits behavior;
- an AST cache hit changes require discovery;
- a materialized function cache is keyed by a lossy mangled name rather than a
  typed materialization key;
- one bootstrap smoke uncovers a new crash frontier not explained by the active
  cache slice;
- cache size grows without a per-layer cap and prune story;
- a disabled cache path is deleted without first classifying whether it is a
  future reuse candidate or an unsafe stale-hit path.

## 14. Ledger sync

- task ledger: `TODO.md`
- architecture boundary SDD: `docs/compiler_architecture_sdd.md`
- existing cache code:
  - `src/compiler/cli.cr`
  - `src/compiler/lsp/ast_cache.cr`
  - `src/compiler/lsp/project_cache.cr`
  - `src/compiler/lsp/prelude_cache.cr`
  - `src/compiler/lsp/semantic_token_cache.cr`
- falsifier matrix:
  - `regression_tests/*_repro.sh`
  - `regression_tests/*_probe.sh`
- future census:
  - `docs/incremental_build_cache_census.md`

## 15. Implementation seals

### Slice A: Cache census and certificate trace

Source/spec:

- `src/compiler/cli.cr` options and cache paths,
- LSP cache headers and invalidation checks,
- current `--stats` timing output.

Falsifiers:

- repeated no-cache build gives identical certificate trace;
- changed source hash changes certificate;
- changed env gate changes certificate only when the gate affects the artifact
  kind.

Evidence:

- no behavior change;
- cache trace OFF by default.

Boundary:

- no cached artifact is consumed.

Next local track:

- declaration summary cache.

### Slice B: Declaration summary cache

Source/spec:

- LSP `ProjectCache` summary serialization,
- compiler declaration collection path,
- require graph scanner.

Falsifiers:

- body-only edit keeps interface hash stable;
- signature edit changes interface hash;
- require edit changes require graph hash;
- stale cache file is rejected.

Evidence:

- shadow-compare cached and fresh summaries;
- no-cache and cache output parity.

Boundary:

- no AST/HIR/MIR body reuse.

Next local track:

- AST cache read rehabilitation.

### Slice C: AST cache read rehabilitation

Source/spec:

- `LSP::AstCache`,
- compiler `parse_file_recursive`,
- require scanning and source fallback.

Falsifiers:

- AST roundtrip parity,
- require discovery parity,
- span/source string parity for diagnostics,
- bootstrap smoke.

Evidence:

- env-gated AST read;
- default OFF until bootstrap parity.

Boundary:

- no semantic/materialization cache.

Next local track:

- semantic/materialization caches after architecture boundaries are sealed.

## 16. Promotion criteria

No cache layer may become default-on for compiler builds until:

- it has a complete certificate,
- no-cache vs cache parity passes on focused falsifiers,
- cache size is bounded,
- stale/missing/corrupt artifacts rebuild cleanly,
- relevant bootstrap smoke passes,
- the owner explicitly promotes the layer.

Tail cache promotion is separate from semantic cache promotion.
