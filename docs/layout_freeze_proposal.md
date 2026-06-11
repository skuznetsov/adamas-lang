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

## Proposed freeze/update rule (B1 — NOT flipped yet)

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
