# Phase 1: Semantic Identity Layer — Lifecycle & Invalidation Rules

## 1. SemanticTypeId Lifecycle

**Creation:** `SemanticTypeInternTable.intern(key)` assigns a unique `UInt32` id.

**Stability scope:** One compilation run. Ids are NOT stable across runs
(the intern table starts at 0 each time).

**Equality contract:** Two `SemanticTypeId` values are equal iff their `.id` matches.
Since ids are assigned by the intern table (not hashed), there are zero collisions.

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
- `arg_types`: ordered list of argument semantic types
- `block_type`: semantic type of block argument (if any)
- `named_arg_types`: ordered list of `{name, type}` for named arguments

**Equality contract:** All components must match. Arrays are defensively copied
in the constructor, so mutation of the original array after key creation does
not affect the key.

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

## 5. DryRunTracker Lifecycle

**Purpose:** Observation-only side channel. Counts how many body inferences
would be cache hits if a DefInstanceKey cache existed.

**Behavior guarantee:** The tracker changes NO compilation behavior.
It only observes and reports statistics.

**Activation:** `CRYSTAL_V2_IDENTITY_DRY_RUN=1` environment variable.

**Output:** After compilation, dumps to STDERR:
```
[IDENTITY_DRY_RUN] lookups=N hits=N misses=N hit_rate=N%
[IDENTITY_DRY_RUN] unique_keys=N duplicate_keys=N interned_types=N
```

## 6. Boundary: SemanticTypeId vs HIR TypeRef

**Rule:** SemanticTypeId lives in semantic caches and DefInstanceKey.
HIR TypeRef lives in HIR Module, functions, instructions.

**Crossing the boundary:** Only through `SemanticToHIRAdapter.resolve()`.

**Never cross back:** HIR TypeRef must not appear in DefInstanceKey or
any semantic cache key. The adapter's reverse lookup is for diagnostics only.

## 7. Dry-Run Results (hello world)

**Key components used in dry-run (SURROGATE, not canonical):**
- `DryRunDefKey`: `{resolved_arena.object_id, node.object_id}` — a temporary
  surrogate for def identity. This is NOT the canonical `DefIdentity{arena_id,
  ExprId.index}` because ExprId is not yet available at inference call sites.
  The surrogate is injective (each heap DefNode has a unique object_id) but
  is explicitly separate from the Phase 1 identity contract.
- Receiver: interned `self_type_name`
- Args: interned parameter type annotations (UNKNOWN for unannotated params)
- Block: interned block parameter type annotation (if present)
- NOT yet included: generic type parameters, inferred call-site arg types,
  named argument types

**Interpretation:** The hit rate measures repeated body inference for the same
surrogate def key + receiver + declared-param-type combination. It does NOT yet
capture call-site specialization (where the same def is analyzed with different
inferred arg types). A real Phase 4 cache would key on canonical DefIdentity +
inferred types at the call site, not declared annotations — so actual cache hit
rates will differ.

The dry-run is a directional signal showing that many body walks target the
same def+receiver combination, not a precise prediction of Phase 4 savings.

**Path to canonical keying:** Thread ExprId through to
`infer_concrete_return_type_from_body` call sites (ExprId is available at the
iteration level, e.g. `body_ids.each do |member_id|`, but is not currently
passed through). Once plumbed, the surrogate will be replaced with real
`DefIdentity` + `DefInstanceKey`.

```
lookups=5561  hits=3147  misses=2414  hit_rate=56.6%
unique_keys=2414  duplicate_keys=573  interned_types=399
```

Compare with Phase 0's `body_infer_dupes=401` (keyed by DefNode.object_id only).
The enriched key finds 3147 hits because the same syntactic def can be analyzed
multiple times with the same receiver — a genuine cache opportunity.
