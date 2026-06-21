# C-narrow-a placement — implementation brief (CAUTION, behavior)

Status: **PROPOSED. Implementation design for GPT review BEFORE the codegen edit.**
Companion to `docs/abi_struct_value_c_packet.md` (§4 C-narrow-a) and the shipped
read-only preflight (`b929e23b`, gate `ADAMAS_CNARROW_A_PREFLIGHT`). GPT gave a
CONDITIONAL GO for C-narrow-a behavior; this brief grounds the *how* in the actual
lowering code and surfaces the one hard ordering problem before any edit.

This is the FIRST behavior/codegen change of the C arc — CAUTION-tier, and it lands
in the **UAF-critical escape-analysis path** (the memory invariant: *any escape
analysis miss under Stack = use-after-free*, unlike GC where it is only a missed
opt). So it gets a design + pre-mortem + the already-built falsifier reducers as
guards before the edit, per the project's CAUTION cadence.

---

## 1. Chosen mechanism — EXTEND Shape-C stack promotion (not a push rewrite)

Reconnaissance result: do NOT reimplement `Array(T)#<<` to construct-in-buffer
(that reproduces Array capacity/size internals = a second oracle = GPT hard-stop).
Instead reuse the PROVEN Shape-C stack-promotion machinery
(`lower_stack_local_struct_allocator_call`, `hir_to_mir.cr:8201`) which already does
construct-in-place ON THE STACK for non-escaping `T.new`.

**The win:** at an eligible `arr << T.new(args)`, the transient `T` becomes a stack
`alloca` (initialized in place) instead of a heap `__adamas_malloc64`; the A′ push
then memcpy's its bytes into the inline buffer slot. In a loop the alloca is
function-scoped → **0 heap allocs across all iterations** = the C-narrow-a DoD
("eligible Vec3 push loses transient `$Dnew`/`__adamas_malloc64`").

**Why this is sound (the lynchpin, already verified):** under A′
(`ADAMAS_INLINE_VALUE_ARRAY_STORAGE`), `Array(T)#<<` for an inline-eligible T
**memcpy's the value bytes** into `@buffer[size]` and does NOT store the transient
pointer (verified prior work: OFF=`store ptr %value`, A′-ON=`memcpy(slot,value,stride)`).
So the `<<` is a **borrow** of the transient (reads its bytes, copies, discards the
pointer) → the transient's identity never escapes → stack-promotion is safe. The
moment A′ is OFF (or T is not inline-eligible), the push stores the *pointer* → the
transient escapes → it MUST stay heap. This makes the gate self-consistent.

## 2. The two hooks (both in the escape path — the UAF-critical edit)

Today both gates correctly REJECT the eligible push transient (it is `ArgEscape`):

- **Lifetime gate** (`:8209`): `call.lifetime == StackLocal` required; an
  `arr << T.new(..)` ctor is `ArgEscape` → rejected.
- **Use-walk** (`stack_local_struct_constructor_uses_safe?` → `hir_value_stack_safety`
  → `stack_safety_at_call_use`): the `<<` call use is treated as a leak (the param
  may be stored).

The placement slice flips BOTH, fail-closed, ONLY for the proven-borrow case:
treat a monomorphic `Array(T)#<<`/`#push` use of an `inline_array_storage_eligible`
T as a **borrow (non-leaking)**, and allow the ctor to promote despite the nominal
`ArgEscape` when its ONLY escape is such a push.

## 3. THE ORDERING PROBLEM (the real design decision — flag for review)

`inline_array_storage_eligible(T)` is computed by `populate_array_bulk_op_facts`,
which needs the **fully lowered MIR** (`Array(T)#` bodies must exist). But the
stack-promo decision is made **during** `lower_call` (HIR→MIR), *before* those
bodies and facts exist. So the eligibility fact the gate must consume is NOT
available at the decision point. Two sound resolutions (GPT hard-stop says: extend
facts/preflight, do not re-derive blindly):

- **(A) Post-lowering MIR transform.** Keep lowering as-is (heap malloc); add a late
  MIR pass (after `populate_array_bulk_op_facts`, same place the preflight runs) that
  rewrites a heap-`malloc` transient → stack `alloca` when its sole consumer is an
  A′-inline push of an eligible T. Pro: consumes the already-proven facts directly;
  no during-lowering re-derivation. Con: a malloc→alloca rewrite on lowered MIR
  (must also drop the matching memcpy-source indirection / fix the def-use).
- **(B) Pre-pass eligibility mark.** Run a lighter storage-eligibility proxy BEFORE
  lowering (leaf_storage_pod_struct? is registry-only and *is* available early), mark
  the eligible ctor HIR calls, and have `lower_stack_local_struct_allocator_call`
  consume the mark. Con: the proxy is weaker than the full
  `inline_array_storage_eligible` (no bulk-coverage / to_unsafe-escape proof early) →
  would need the full gate re-checked, risking a split oracle.

**Recommendation: (A) post-lowering transform** — it consumes the SAME facts the A′
behavior and the preflight already prove (no second oracle, no early proxy), at the
SAME pipeline point the preflight already runs. The preflight's `eligible` verdict
(ctor↔push pair, sole-use via copy-closure) is the exact selector; persist it as a
durable mark in the read-only preflight, then the transform consumes
`preflight_eligible && inline_array_storage_eligible(T)`.

## 4. Gate + fail-closed conditions

- New env gate `ADAMAS_CNARROW_A_PLACEMENT`, **default OFF**. Gate-OFF byte-identical.
- **Requires A′ on** (`ADAMAS_INLINE_VALUE_ARRAY_STORAGE`): the soundness depends on
  the push being a by-value memcpy. If A′ is off, placement is force-off (the push
  stores a pointer → transient escapes → heap mandatory). Document the coupling; the
  gate checks it and no-ops if A′ is off.
- Promote ONLY when ALL hold (fail-closed; any doubt → existing heap path):
  `preflight_eligible` (ctor↔push, fresh sole-use via copy-closure, monomorphic
  Array(T)#push) `&& inline_array_storage_eligible(T)` `&& semantic_recursive_pod(T)`.
  erased/non-monomorphic/Pair(not-storage)/ref-owning(class)/reused → never promoted
  (the preflight already proves these NOT eligible; the transform must not re-derive).

## 5. DoD — mapped to GPT's 5 checks + the existing reducers

1. **construct invariants ON==OFF** → `cnarrow_a_construct_invariants.sh` re-run WITH
   `ADAMAS_CNARROW_A_PLACEMENT=1 ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1`; RESULT line
   identical to legacy (`order_ok grow_ok partial_ok` all true).
2. **eligibility negatives stay not-fused** → extend `cnarrow_a_preflight_eligibility`
   or a new placement reducer with `ADAMAS_STACK_PROMO_TRACE`: Pair / reused / Box /
   non-monomorphic emit NO placement; Vec3 eligible DOES.
3. **eligible Vec3 push loses the transient malloc** → IR assert: in the push loop,
   `V3` ctor `__adamas_malloc64` count → 0 (becomes `alloca`); checksum identical.
4. **Pair / reused / ref-owning / non-monomorphic do NOT get placement** → (2).
5. **gate-OFF byte-identical** OR broader suite green → normalized IR diff + the
   139/139 + 36/36 suite at gate-OFF, plus s2b smoke unchanged.

## 6. Hard-stop adherence

The transform consumes (a) the preflight `eligible` verdict (persisted mark) and (b)
the A′ `inline_array_storage_eligible(T)` fact — both already proven, read-only. It
builds NO new storage/provenance oracle. If implementation reveals the transform must
re-derive @buffer provenance or storage eligibility, STOP and persist the missing fact
in the preflight (per GPT), do not patch the backend blindly.

## 7. 48-hour pre-mortem (CAUTION)

- **Likely breakage:** an escape-analysis miss promotes a transient whose pointer IS
  retained → UAF. **Detection:** the construct-invariant + behavior-identity reducers
  (a UAF would corrupt readback / crash under run_safe). **Mitigation:** the gate
  requires FULL `inline_array_storage_eligible` (which already proves bulk-op coverage
  + no `to_unsafe` escape), so every path that could retain the pointer is excluded;
  default OFF; A′-coupling required.
- **Fastest signal:** `cnarrow_a_construct_invariants.sh` + `inline_value_array_storage_behavior.sh`
  run with both gates on; any RESULT drift or crash = stop.
- **Rollback:** single gated transform; gate-OFF removes it entirely; tree committed.

## 8. NEXT

Owner/GPT review of mechanism (§1), the ordering resolution (§3, recommend A), and the
gate coupling (§4). Then implement the post-lowering transform UNCOMMITTED, verify §5,
commit as a separate gated CAUTION slice. C-narrow-b (load) stays deferred.
