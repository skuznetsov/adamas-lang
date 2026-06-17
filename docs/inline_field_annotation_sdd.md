# `@[Inline]` Field-Embedding Annotation — Design + Hostile Review

**Status: DEFERRED (conditional).** This is a design record, not an approved
implementation plan. It captures the idea, the hostile Quadrumvirate that
stress-tested it, what survived, the hard preconditions, and the dependency
ordering that must hold before any code is written. Reviewed 2026-06-16 on
branch `abi-rework`.

## 1. Idea

A field-level annotation `@[Inline]` on a class/instance variable tells the
compiler to **embed the field's value bytes directly into the parent object's
layout** (flattened), instead of holding the field via an 8-byte pointer to a
separately-allocated box ("bake the child into the parent").

```crystal
class Outer
  @[Inline] @inner : Inner   # Inner's fields embedded into Outer's layout
end
```

Wins (when sound): one allocation instead of two, contiguous fields, no separate
rc/header for the child, no pointer indirection on `outer.inner.x` (single
composed GEP).

Precedent: original Crystal already embeds **struct** ivars by value (no
annotation); Adamas currently heap-boxes them (`CLAUDE.md`). So `@[Inline]`
(a) catches struct fields up to Crystal, and (b) extends embedding to
**monomorphic class** fields, which Crystal never inlines.

## 2. Hostile Quadrumvirate (2026-06-16)

Run explicitly to falsify the idea and to check for epistemic sycophancy after
several agreeing turns. Verdict: **VULNERABLE as stated; ROBUST only scoped and
dependency-ordered.**

### Verified findings

- **ATTACK C — fights a load-bearing invariant (CONFIRMED).** `CLAUDE.md`:
  "FieldGet always loads a pointer — do NOT skip load for struct types." No-load
  offset composition exists today only for *container element strides*
  (`inline_container_struct_type?`, llvm_backend.cr:2796), not for arbitrary
  nested fields. Inlining requires new field-access lowering inside the struct
  ABI, which the memory notes call the most dangerous part of the hybrid model
  (4 reprs, 3 unsynchronized oracles).

- **ATTACK D/E — adds #4 repr-flip surface (CONFIRMED, decisive).** `@[Inline]`
  makes "field of type T" sometimes a pointer and sometimes inline bytes. The #4
  bootstrap blocker is exactly a producer/consumer repr-flip (String↔Slice). The
  3 layout oracles are **not consolidated**: HIR `field_storage_size_impl` reads
  `LayoutContract.user_struct_inline?`, but LLVM `inline_container_struct_type?`
  is still a name-match and `mir_field_storage_size` does not route through the
  contract. On un-consolidated oracles, any consumer that "always loads a
  pointer" on an inlined field reads inline bytes **as a pointer** → a
  non-deterministic crash indistinguishable from #4.

- **ATTACK B — finality precondition (REFUTED, i.e. implementable).** Finality is
  queryable: `subclasses_for(name)` / `has_subclasses` (hir_to_mir.cr:6826).
  Monomorphism can be enforced at compile time after RTA (closed world).

- **ATTACK A — "LLVM already removes the indirection" (REFUTED).** A field-pointer
  load comes from memory and is not invariant across calls, so LLVM keeps it.
  The inline win is real for hot fields. The idea is not worthless — it is
  mis-ordered and mis-scoped.

### Demand measurement (cargo-cult / value-proxy check)

Of 1418 ivar declarations in `src/compiler/`:
- 563 primitive (already inline — N/A)
- 547 container (Array/Hash/… — dynamically sized, cannot inline; the dominant
  allocation surface is **out of scope** for this annotation)
- 272 nilable (v1-disqualified)
- → genuine monomorphic owned-class-field candidates ≈ a few dozen (~2-3%).

ROI by count is narrow. ROI by access-frequency (the dimension that matters) is
**unmeasured**. Measure frequency before investing in the class-field case.

### Sycophancy correction

Earlier claims that did not survive: "plugs cleanly into LayoutContract" (false —
oracles un-consolidated, consumers bypass the contract), "safe incremental path"
(omitted that it feeds #4), "big perf win" (undersold demand narrowness).

## 3. What survives, and the dependency order

1. **Blocked-until (hard gate):** the 3 layout oracles are consolidated
   (ABI-rework steps 1b/1c/2 — route MIR `mir_field_storage_size` and LLVM
   `inline_container_struct_type?` through `LayoutContract`) **and** #4
   (the repr-flip producer/consumer) is fixed. Doing `@[Inline]` before this
   injects #4-class non-deterministic crashes.

2. **v1 scope = struct fields only.** This is the deferred step-4 work made
   opt-in and incremental, with original Crystal as the truth oracle. Same
   mechanism, per-field, gated each commit.

3. **Class-field inline = deferred** behind v1 plus an interior-reference
   leak/escape check (else a leaked interior ref = UAF that mimics #4).

## 4. Hard preconditions (compiler MUST error, never silently miscompile)

`@[Inline]` accepted iff the field is:
- **monomorphic / final** — `subclasses_for(T)` empty (fixed slot size; else a
  larger subtype overflows the slot);
- **non-recursive** — `T` does not transitively `@[Inline]` itself (else infinite
  size; linked lists cannot inline `@next`);
- **non-nilable** — no pointer ⇒ no null to mean "absent"; nilable needs a
  presence flag (out of v1);
- **assign-once in `initialize`** — no reassignment (reassigning an embedded value
  is memcpy, which diverges from reference identity: `outer.inner = x` would make
  `outer.inner.same?(x)` false).

Remaining footgun (class-field case): a read `y = outer.inner` yields an interior
pointer into the parent box. If `y` outlives the parent → UAF. v1 (struct-only)
sidesteps this for value semantics; the class-field extension needs a leak check
or an explicit unchecked contract + lint.

C-ABI / `@[Extern]` lib structs keep their dedicated inline C layout regardless
(SDD §5 guard-only); they are not affected by this annotation.

## 5. Kill-conditions

Abandon or re-scope if any hold:
- frequency profiling shows the candidate fields are cold (no hot-path indirection
  to remove);
- oracle consolidation proves infeasible without a larger rewrite (then the #4
  surface cannot be bounded);
- the struct-field v1 cannot reach Crystal-layout parity on the regression +
  bootstrap gates.

## 6. Relationship to existing work

- Subsumes the deferred **step-4 inline struct** (`abi_struct_value_sdd.md` §0) as
  the opt-in, per-field, non-big-bang path — directly avoiding the global-flip
  startup crash observed when flipping `user_struct_inline?` wholesale.
- Depends on the **LayoutContract** consolidation (`layout_contract.cr`,
  ABI-rework 1b/1c/2).
- Must not precede the **#4** repr-flip fix
  (`[[s2b-startup-crash-rc-overfree-refuted]]`).
