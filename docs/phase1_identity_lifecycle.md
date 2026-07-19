# Phase 1: Semantic Identity Layer — Lifecycle & Invalidation Rules

## 1. SemanticTypeId Lifecycle

**Creation:** `SemanticTypeInternTable.intern(key)` assigns an ordinal owned by
that table.

**Representation and authority:** The current candidate represents each
`SemanticTypeId` as a 16B handle containing the owner interner reference and a
`UInt32` ordinal. Equality and hashing use the pair
`(owner interner reference, ordinal)`; the owner validates that the ordinal was
issued before the handle is canonical. The same ordinal from two interner
instances is therefore unequal. `NameId` uses the same 16B representation and
authority with `NameInternTable` as its owner. No separate `IdentityScope` token
participates.

**Stability scope:** One compilation run. Ordinals are NOT stable across runs
(the interner starts at 0 each time). The 16B size is a current representation
fact only; residual performance/memory measurement is required and no speed
claim follows.

**Invalidation:** SemanticTypeId values become invalid when the `SemanticTypeInternTable`
that created them is discarded (end of compilation).

## 2. DefIdentity Lifecycle

**What counts as "same def":**
- Same `AstArena` (by object_id) AND same `ExprId.index` within that arena.
- This identifies a syntactic Def node, not a typed instantiation.
- Reopened classes produce different Def nodes in the same or different arenas,
  so they get different DefIdentity values. This is correct — reopened defs
  are separate syntax trees even if they share a method name.

**Stability scope:** One compilation run. Arena object_ids are heap addresses,
stable within a process but not across runs.

**What does NOT determine identity:**
- Method name (two overloads of `foo` have different DefIdentity)
- Mangled name
- HIR FunctionId
- Type annotations (those go into DefInstanceKey, not DefIdentity)

## 3. DefInstanceKey Lifecycle

**What it represents:** A unique typed instantiation of a def — the same def
called with different argument types produces different keys.

**Components:**
- `def_identity`: which syntactic def
- `receiver_type`: semantic type of receiver (nil for top-level)
- `arg_types`: ordered list of argument semantic types, held by an owned
  immutable value carrier
- `block_type`: semantic type of block argument (if any)
- `named_arg_types`: canonical ordered list of `{NameId, SemanticTypeId}`
  pairs; source spellings remain diagnostic reverse-lookup data only

**Equality contract:** All components must match. Generic/tuple components and
named-argument pairs are copied into immutable value carriers, so mutation of
caller-owned arrays after key creation cannot change equality or hashing. The
`SemanticTypeId` and `NameId` components compare by their owner-interner
reference plus ordinal; equal ordinals from different tables are unequal.

**Cache semantics (future Phase 4):**
- First encounter with a DefInstanceKey → analyze body, cache result
- Second encounter with the same key → return cached result
- This is the demand-driven equivalent of original Crystal's `def_instances`

**Invalidation rules (for future cache):**
- Key becomes invalid if the underlying DefIdentity's arena is freed
  (would only happen with incremental compilation, not in current design)
- Key remains valid for the entire compilation run
- No time-based invalidation needed within a single compile

## 4. SemanticToHIRAdapter Lifecycle

**Purpose:** Maps `SemanticTypeId → HIR::TypeRef` at the emission boundary.

**Direction:** One-way. Semantic → HIR only. The reverse map exists for
diagnostics but must NOT be used for cache keys or identity.

**Population:** The adapter is populated during HIR emission. Each semantic type
that needs an HIR representation gets registered exactly once.

**Invalidation:** Same as SemanticTypeInternTable — valid for one compilation run.

## 5. IdentityDryRunTracker Lifecycle — RETIRED / REFUTED

As of 2026-07-18, `IdentityDryRunTracker` and
`src/compiler/semantic/identity/dry_run_tracker.cr` are removed from the
isolated candidate. The old tracker was a definition-annotation/body-infer
proxy: it observed declarations while inferring bodies, not the semantic
callsite resolution that chooses receiver, argument, block, and named types.
It therefore could not establish `ResolutionId` or typed identity continuity.

`ADAMAS_IDENTITY_DRY_RUN` and the `[IDENTITY_DRY_RUN]` output are retired
interfaces, not supported activation or evidence paths. Historical dry-run
counts below are archival measurements from the pre-removal experiment only;
they are not current behavior, admission evidence, or a cache-success claim.

The replacement substrate is compile-session scoped and owner-scoped:
`NameId` and `SemanticTypeId` are current 16B handles whose equality/hash
authority is `(owner interner reference, ordinal)`, with owner validation of
issued ordinals; no separate `IdentityScope` token is used. `NameId` owns
canonical name ordinals, `SemanticTypeId` owns interned semantic type ordinals,
and `DefInstanceKey` combines those with `DefIdentity` and immutable value
carriers. The 16B representation still needs residual performance/memory
measurement and is not a speed claim. This substrate is a prerequisite for a
future producer record; it is not itself a semantic callsite producer or a
promoted T1 consumer.

## 6. Boundary: SemanticTypeId vs HIR TypeRef

**Rule:** SemanticTypeId lives in semantic caches and DefInstanceKey.
HIR TypeRef lives in HIR Module, functions, instructions.

**Crossing the boundary:** Only through `SemanticToHIRAdapter.resolve()`.

**Never cross back:** HIR TypeRef must not appear in DefInstanceKey or
any semantic cache key. The adapter's reverse lookup is for diagnostics only.

## 7. Historical Dry-Run Results (archival; not current)

The following numbers document the retired tracker experiment and must not be
read as evidence that the current candidate still runs this path.

**Dual-path keying:**

The dry-run uses two identity paths:

1. **Canonical** (34.8% of lookups): `DefIdentity{arena.object_id, ExprId.index}`
   via `DefInstanceKey`. Used at 14 call sites where ExprId is available from
   arena iteration loops (`body_ids.each do |member_id|` etc.).

2. **Surrogate** (65.2% of lookups): `DryRunDefKey{arena.object_id, node.object_id}`
   via `DryRunInstanceKey`. Used at ~10 call sites where DefNode arrives as a
   function parameter without an associated ExprId.

Both paths include:
- Receiver: interned `self_type_name`
- Args: interned parameter type annotations (UNKNOWN for unannotated params)
- Block: interned block parameter type annotation (if present)
- NOT yet included: generic type parameters, inferred call-site arg types,
  named argument types

**Interpretation:** The hit rate is a directional signal. A real Phase 4 cache
would key on inferred call-site types, not declared annotations. The canonical
path satisfies the Phase 1 identity contract; the surrogate path is a temporary
fallback that will shrink as more call sites get ExprId plumbing.

**Remaining surrogate call sites** (10 of 24):
- `register_module_method_from_def(member, ...)` — Pattern D
- `registered_concrete_class_method_def(node, ...)` — Pattern H
- `infer_return_type_from_callsite(node, ...)` — Pattern I
- `infer_return_type_from_body_without_callsite(node, ...)` — Pattern J
- `force_lower_function_for_return_type` — Pattern L
- `register_type_method_from_def` effective_member — Pattern K

These would require adding ExprId parameters to intermediate functions.

```
lookups=5561  hits=3019  misses=2542  hit_rate=54.3%
canonical=1934(34.8%)  surrogate=3627
unique_keys=2542 (canonical=1608 surrogate=934)  interned_types=399
```

The dry-run hook runs AFTER final arena resolution (including
`@function_def_arenas` override), so the arena_id in DefIdentity matches
the arena actually used for body inference.

Compare with Phase 0's `body_infer_dupes=401` (keyed by DefNode.object_id only).
The enriched key finds 3019 hits — a genuine cache opportunity.
