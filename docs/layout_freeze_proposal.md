# B0 Registration Trace: Ghost Type Identities and the Stale-Slot Hole

Status: DIAGNOSTIC FINDINGS + PROPOSAL. No behavior change in this commit.
Probe: `ADAMAS_LAYOUT_PROBE=1 ADAMAS_LAYOUT_PROBE_TRACE='<name-substrings>'`
(see `src/compiler/layout_probe.cr`). Evidence from
`regression_tests/slice_uint8_ivar_slot_overlap_repro.sh` (open bug, expected FAIL).

## Finding B0-1: ghost mechanism is uniform — Generic placeholder vs concrete kind

`HIR::Module#intern_type` identity is `(name, kind, type_params)`. Type-annotation
resolution interns instantiated generic names as `kind=Generic` *before* the
generic is monomorphized; `register_concrete_class` later interns the same name
as `kind=Struct` (Slice, Atomic) or `kind=Class` (Deque). The bucket treats the
kind mismatch as a different type and mints a second id.

All five traced ghosts follow exactly this pattern (single compile):

| name | first intern | second intern |
|---|---|---|
| `Slice(UInt8)` | id 156 kind=Generic | id 891 kind=Struct |
| `Atomic(Bool)` | id 350 kind=Generic | id 734 kind=Struct |
| `Atomic(Int32)` | id 358 kind=Generic | id 819 kind=Struct |
| `Deque(Fiber)` | id 393 kind=Generic | id 1200 kind=Class |
| `Deque(Fiber::Stack)` | id 728 kind=Generic | id 1206 kind=Class |

Class ghosts are lower-risk (classes are always pointer-sized in fields);
struct ghosts are the corruption family.

**Proc reclassified**: the earlier "Proc has 3 ids" finding was an undercount of
a different, mostly benign family — bare `Proc` is the display name for DOZENS
of distinct `kind=Proc` entries distinguished by `type_params` (one per
signature), which is by design. The genuine ghost inside it is a single
`kind=Struct, params=0` entry (id 700 in the reducer compile) — the stdlib
`struct Proc` registration colliding with the signature entries — i.e. the
same Generic/concrete-kind split as Finding B0-1.

## Finding B0-2: the stale slot is an ORDERING hole, not a stale size

Probe timeline for the overlap reducer (Holder with a `Slice(UInt8)` ivar):

1. `intern_type.new` — `Slice(UInt8)` id 156 kind=Generic (no class_info).
2. `register_concrete_class.final Holder` — Holder layout computed NOW.
   `type_size(Slice(UInt8))` hits `type_size.ref_fallback` with
   `by_id:none by_name:none` → **8 bytes (reference fallback)**. The 8-byte
   slot is born here: there is no class_info to consult at all.
3. `intern_type.ghost` — `Slice(UInt8)` id 891 kind=Struct (monomorphization).
4. `register_concrete_class.final Slice(UInt8)` — size 0 → **16**, ivars 3.
5. From now on `type_size` returns 16 via BOTH ids (`struct_by_id` for 891,
   `struct_by_name` for 156). The registry heals itself — but Holder's frozen
   offsets never do.

So `@class_info` is never wrong; the *owner* layout was computed against a
missing entry and is never recomputed.

## Finding B0-3: dependent owners are never re-laid-out

The global realign pass `align_all_class_ivars` (called from
`fixup_inherited_ivars`, `cli.cr:2149`) runs at a fixed pipeline point, BEFORE
late monomorphizations that happen during body lowering.
`monomorphize_generic_class` then realigns ONLY the newly created class
(`align_class_ivars(specialized_name)`, with a comment admitting
"align_all_class_ivars may have already run before this monomorphization").
Owners whose ivars reference the late-monomorphized struct keep their stale
slots. MIR later lowers stores via the concrete 16-byte view → 16-byte memcopy
into an 8-byte slot → adjacent-field corruption (proven by the reducer).

## B1a0 ledger evidence (ADAMAS_LAYOUT_PROBE_LEDGER=1)

Non-dedup, sequence-numbered event ledger (B0's dedup hid event order). New
rows: `layout_dep` (owner class, ivar, field type, type_size branch, slot),
`layout_dep.stale_owner` (emitted on every `@class_info` write for a type that
previously fed a ref_fallback slot), `layout_dep.healed` (a later re-layout of
the same owner#ivar resolved through a real branch). With the ledger on, ALL
probe rows go through the seq writer, so order is preserved end to end.

Reducer compile, the stale dependency proven in one file:

- Holder is laid out 4× (`register_concrete_class` final realign + align
  passes), every time `Holder#@bytes <- Slice(UInt8) ref_fallback slot=8`
  (seq 3449, 5199, 6854, 8508).
- `Slice(UInt8)` class_info completes only at seq 8718+ (size 0 -> 16),
  emitting `stale_owner:Holder#@bytes` on each subsequent write.
- Holder's LAST layout event is seq 8510 — nothing re-lays it out after the
  completion, and no `healed` row for `Holder#@bytes` ever appears.
- Positive control: the healed mechanism does fire 6× (Time::Span, Time,
  Char::Reader x3, Path owners) — `align_all_class_ivars` convergence heals
  owners whose field types complete BEFORE the global align; the hole is
  strictly types completing after it (late monomorphizations during lowering).
- Scope note for B1c: `stale_owner` rows are dominated by classes and
  pointers (String, IO, Pointer(...)) for which the 8-byte fallback is the
  CORRECT field size; the corruption family is the value-struct subset
  (Slice(UInt8), Atomic(Int32), ...). The flip must filter to value-like
  structs, not ban the class fallback.

## B1a SHIPPED: pre-lowering forced monomorphization (not mid-lowering relayout)

The flip landed as `force_monomorphize_ref_fallback_types`, called from
`fixup_inherited_ivars` immediately BEFORE the final `align_all_class_ivars`
pass. The always-on owner/ivar layout context records every
`type_size.ref_fallback` consumption into `@layout_ref_fallback_owners`
(field-type name -> owner set); at the fixed pre-lowering point, every
recorded key that still has no class_info, parses as a generic
instantiation, and whose template is a **value struct** is force-
monomorphized (fixpoint: new registrations may record new deps). The
existing align convergence pass then recomputes all dependent owners
against real sizes. Ledger confirms: `Holder#@bytes` now gets a
`layout_dep.healed` row and lays out via `struct_by_id slot=16`.

Three branches were falsified empirically on the way:

- **Mid-lowering relayout cascade (REJECTED, empirically)**: re-laying-out
  dependent owners + invalidating their lowered bodies from inside
  `register_concrete_class` breaks functions already in progress — they
  keep mixed old/new offsets (`invalidate_lowered_layout_functions`
  necessarily skips in-progress lowering). Observed: `IO::FileDescriptor`
  (holds `Atomic(Int32)`) relaid mid-pipeline → hello-world printed NUL
  garbage. Layout updates after lowering has started are unsound, period.
- **Unfiltered force-mono (REJECTED, empirically)**: forcing ALL generic
  fallback keys (classes included) ballooned stage2 self-compile past the
  4096MB `run_safe` budget (killed at 4.34GB / 204s,
  `p2_generated_stage2_no_prelude_puts_guard`). Class fields are
  pointer-sized — the fallback was already correct for them, so the
  struct filter (`GenericClassTemplate#is_struct`) is both the
  correctness-scope and the memory fix.
- **Forcing magic bases (REJECTED, empirically)**: even with the struct
  filter, forcing `StaticArray(UInt64, BIGINT_LIMBS)` (constant size arg,
  unresolved at that point) minted a bogus specialization whose lowered
  `map$$block` emitted invalid LLVM (`inttoptr ptr -> ptr`) — llc failed
  the whole stage2 self-build
  (`p2_generated_stage2_lookup_lazy_enum_no_prelude`, A/B-confirmed
  against the `8241cf76` baseline). StaticArray/Tuple/Proc/Pointer/Union
  have dedicated layout paths (sa_size branch, tuple element offsets,
  pointer word) and are skip-listed; variadic Tuple could additionally
  raise on template arity.

Residual hole (accepted, diagnosed by ledger): owners REGISTERED during
lowering whose struct field types monomorphize even later still get stale
slots — same family, now strictly narrower. The B1c on-demand
registration step is the structural close for that.

## B1c SHIPPED: on-demand monomorphization in the type_size fallback

Evidence pass after B1a (reducer-compile ledger): every owner#ivar whose
LAST `layout_dep` was `ref_fallback` either healed or its field type is a
class/pointer (8 correct) — the only struct leftovers were `Proc`
(pointer-carrier by design). All layout events ended before the first MIR
field event, i.e. the PRE-lowering family was fully closed. The residual
family was then reproduced live (`late_owner_generic_struct_field_slot_repro`):
a generic owner monomorphized only during body lowering
(`LateOwner(Int64)`) consumed `type_size(MyPair(Int64))` before that
struct had class_info — ref_fallback slot=8 for a 16-byte struct,
`stale_owner` with no `healed` row, runtime garbage from `@pair`. B1b
(intern kind-upgrade) cannot reduce this family: the slot is born from a
MISSING class_info, not from ghost-id confusion — so B1c shipped first
(matching the agreed exception to the B1b-first default).

Mechanism: when the `type_size` reference fallback fires while an owner
layout is being computed (`@layout_owner_context` set), the field type is
run through the same candidate filter as the B1a fixpoint
(`try_monomorphize_layout_candidate`: alias-resolve, generic split, magic-
base skip-list, `template.is_struct`) and monomorphized ON DEMAND, so the
owner's FIRST layout is already correct — no relayout needed (relayout
after lowering started is unsound, see B1a falsification #1).

Guards, each empirically motivated:

- **Armed only after the B1a fixpoint** (`@layout_on_demand_mono_armed`).
  Firing during initial prelude registration monomorphized against
  INCOMPLETE templates/reopenings: the partial specialization poisoned
  `@monomorphized`, the real instantiation never registered, `Slice(UInt8)`
  vanished from class_info, owners deflated (IO::FileDescriptor 168→160),
  and hello-world flaked SIGBUS in malloc (heap corruption) ~6/10. Before
  arming, the fallback records into `@layout_ref_fallback_owners` exactly
  as under B1a.
- **`@suppress_monomorphization` respected** — suppressed registration
  phases keep recording-only behavior.
- **Re-entrancy set** (`@layout_mono_in_progress`) breaks self/mutual
  recursion cycles.
- **Owner context nil-swapped** around the nested monomorphization so the
  nested registration does not attribute its own field-size consumption to
  the outer owner.
- `align_all_class_ivars` now iterates a key SNAPSHOT: the on-demand path
  can insert new class_info entries mid-pass, and inserting into a Hash
  being iterated is unsafe; the convergence loop picks up knock-on changes.

## Proposed freeze/update rule (B1 — original proposal, B1a now shipped)

Flip order chosen so each step is independently falsifiable by the probe:

1. **B1a — converge-then-freeze.** Re-run `align_all_class_ivars` to
   convergence at a final point AFTER all monomorphizations and before MIR
   lowering; then freeze: any `@class_info` write after the freeze point is a
   diagnostic error (env-gated assert `ADAMAS_LAYOUT_FREEZE=1` first, hard
   assert later). Requires invalidating already-lowered functions whose layout
   changed (`invalidate_lowered_layout_functions` exists). This alone fixes the
   reducer-class corruption.
2. **B1b — kind-upgrade interning.** `intern_type` must not mint a new id when
   a `Generic` placeholder exists for the same name: upgrade the placeholder
   entry in place (the `upgrade_module_type_for_class` precedent for
   Module→Class). Kills ghost ids; ids become stable identities for Layout.
3. **B1c — no silent reference fallback.** `type_size` reaching the pointer
   fallback for a name that is a known struct/generic instantiation candidate
   should either trigger on-demand registration or mark the owner for
   relayout — never silently size it as a reference.

Risks (why diagnostic-first): B1a changes layout of any class currently
mis-sized (intended, but every consumer of frozen offsets must be invalidated);
B1b alone does NOT fix the reducer (the 8-byte slot comes from missing info,
not from id confusion); B1c can recurse during layout. Each flip lands as its
own commit, gated by: probe shows 0 ghost rows / 0 ref_fallback-for-struct
rows, reducer goes green, combined + p2 suites, s2b probe build.
