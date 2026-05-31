# Method Resolution / Monomorphization Architecture Map & Migration Plan

Status: DESIGN (PROPOSED). Authored against HEAD `39d2026b`.
Scope: HIR-side overload/identity resolution + MIR/LLVM materialization. Does NOT
touch stdlib (`../crystal/src`) or perform global renames. Adamas == renamed
CrystalV2; Crystal stdlib remains a compatible subset layer.

This document is a map + plan only. No behavior change is shipped by writing it.

---

## 0. Motivating defect (grounded, VERIFIED on `39d2026b`)

Reducers (kept in `/tmp`):

- `/tmp/h_struct.cr` — `Hash(Foo, Int32)` where `Foo#hash(hasher)` is untyped.
- `/tmp/h_direct_hash.cr` — direct `puts f.hash`.

Both SEGFAULT (exit 139) when compiled with committed `bin/adamas` and run via
`scripts/run_safe.sh`. VERIFIED 2026-05-30 (commands + crash output captured in
session).

`ADAMAS_NULLPAD_PROBE=1` on `/tmp/h_direct_hash.cr` produces the precise smoking
gun:

```
[NULLPAD_REQUIRED] callee=Foo$Hhash idx=1/2 param=hasher llvm=ptr caller=__adamas_main
```

i.e. `__adamas_main` calls the 2-param `Foo#hash(self, hasher)` with a single
argument; the backend pads `hasher` with `ptr null`; `@x.hash(null)` then derefs
a null `Crystal::Hasher` inside `Hasher#permute`. Same backtrace blocks s2b→s3b
bootstrap (`Hash(TypeRef, UInt32)#[]=` → `key_hash` → `key.hash`). See
`memory/s2b_hasher_null_self_blocker.md` for the full Quadrumvirate trace.

### Root mechanism (VERIFIED by IR + probe; do not re-derive from scratch)

An **untyped** `def hash(hasher)` mangles to the BARE symbol `Foo#hash` (the
`$$Type` suffix is built from param *types*; an untyped param contributes no
suffix). That bare slot is the same one the inherited 0-arg `Object#hash`
monomorph would occupy, so the 0-arg monomorph is never generated. A 0-arg
`f.hash` then resolves arity-blind to the 1-param body and the backend null-pads
the missing `hasher`.

The arity discriminator IS computed at registration (`function_full_name_for_def`
returns `Foo#hash$arity1`) but is OVERRIDDEN at lowering time by a bare
`full_name_override` derived from arity-blind `resolve_method_with_inheritance`.
So **the arity-discriminated identity lives on the registration key but not on
the lowered function name nor on the call binding.**

### Refuted fix direction (do NOT repeat)

Synthesizing a fresh type-discriminated name at CALL/lowering time
(`function_full_name_for_def(... call_arg_types ...)` for untyped regular params)
fixed `h_struct` but caused a runaway monomorphization feedback loop on
generic-heavy code (`mark_live_type → replay_virtual_targets →
lower_function_if_needed_impl → lower_method → lower_call →
infer_virtual_return_type → lookup_function_def_for_call →
monomorphize_generic_class → register_concrete_class → …`), 7.4GB / 20min on one
file. **Constraint for any fix: identity must be established ONCE at DEF
REGISTRATION; resolution must be a name-stable LOOKUP, never a name GENERATOR.**

---

## 1. Current resolution / materialization entry points

The current pipeline overloads a single `String` name with four distinct roles:
**overload family**, **concrete def**, **monomorph instance**, and **LLVM
symbol**. The defect above is a direct consequence of those roles aliasing onto
the same string.

| # | Entry point | File:line | Current role | Failure mode | Target role under unified resolver |
|---|---|---|---|---|---|
| A | `function_full_name_for_def` | ast_to_hir.cr:33360 | Mints the registration KEY from `base_name` + param types + block/named/splat flags + arity discriminator. The identity factory. | Untyped param ⇒ no `$$Type` suffix ⇒ collides with the inherited bare slot. `$arity` discriminator is computed but later overridden. Encodes too many axes into one string. | Becomes the serializer of a structured `MethodInstanceKey`. `base_name` = overload family only; arity/types/flags live in the key struct, not parsed back out of the string. |
| B | `should_register_base_name?` | ast_to_hir.cr:33502 | Decides whether a def also claims the bare `base_name` slot (in addition to its mangled key). | Lets an untyped-param def claim the bare family slot that the inherited 0-arg monomorph needs (`def_params_untyped?` → true). | Replaced by explicit family registration: a `MethodDef`/`DefId` is registered under a stable key; the family slot is a separate index entry, not a co-opted symbol. |
| C | `resolve_method_with_inheritance` | ast_to_hir.cr:47020 | Owner-class resolution ONLY: walks parent chain + included modules, returns a bare `Class#method` string. Comment: "Return base name — caller will mangle." Arity-BLIND. ~64 callers; cache key `"class#method"` with no arity. | Returns `Foo#hash` for a 0-arg call even though `Foo`'s only `hash` needs 1 arg; the inherited `Object#hash` is skipped. This bare string becomes the override that wins over `$arity1`. | One of two collaborators behind the single resolver: an `OwnerResolver` that yields candidate OWNERS. It must NOT choose the callable; arity/type selection is `lookup_function_def_for_call`'s job. Result feeds `Resolution`, never a bare override string. |
| D | `lookup_function_def_for_call` | ast_to_hir.cr:77962 | The de-facto overload scorer. Gathers `overload_keys` (method_index → parent chain → `function_def_overloads`), filters by block/named/splat, scores by arity + type match, returns `{best_name, best_def}`. Heavily cached. | Correct selection here is bypassed: the lazy-lowering path (E) reaches the body via a bare override BEFORE/INSTEAD of trusting this result. Returns a NAME the caller re-mangles. | The CORE of the unified resolver. Promote its output from `{String, DefNode}` to a `Resolution {key : MethodInstanceKey, def : DefNode, owner, …}`. It already does arity+type scoring — it is the right home. |
| E | `lower_function_if_needed_impl` | ast_to_hir.cr:65849 | Materialization: takes a `String name`, reconstructs the def via ~12 fallback branches (direct key, same-module overload, inherited-bare-exact, exact-lookup via D, generic template, reopenings, accessor synth, …), then lowers under a `target_name`. | "Mints identity from requested string": derives both def AND emitted symbol from a string that already lost the structured intent. The bare-override branch (`def_has_untyped_regular_param?` ⇒ override = bare `name`) is the proximate cause of the hash bug. | Materialize a `Resolution` that the resolver already selected. Input becomes `MethodInstanceKey` (or `Resolution`), not a free string. No fallback chain — if no `Resolution`, fail loud. |
| F | `lower_call` (HIR) | ast_to_hir.cr:68619 | Gathers callsite info (receiver, args, arg types, block, named, splat), computes a `func_name` string, drives resolution + emits the HIR `Call`. | Spreads call-shape gathering and name construction across many local branches; produces the bare string that flows to C/E. | Gathers a single `CallShape`, calls ONE resolver entry, receives a `Resolution`, emits the call bound to `Resolution.key`. |
| G | Backend required-arg padding | llvm_backend.cr:20420 (probe at :20472) | When `call_args.size < callee_func.params.size`, pads missing params: source default → literal; else (REQUIRED, no default) → null/0. | Silently masks arity-mismatch resolution bugs (the hash null-self). Also masks a SEPARATE bug: `Crystal::Hasher.new(a,b)` defaults not propagated to MIR `param.default_value` (144/181 of the probe population on the reducer). | Once the resolver guarantees arity-correct binding, the REQUIRED-with-no-default branch becomes FAIL-LOUD (compile error / abort), not silent padding. The default-propagation branch stays but is fed correct defaults. |

### Cross-cutting observation

C, E, and F each independently turn a `(receiver, method, arity, types)` tuple
into a `String`, and D turns it back into `{String, def}`. The string is the
lossy interchange format. The unified resolver replaces the string interchange
with a structured `Resolution`.

---

## 2. Target architecture

```
            ┌─────────────┐
 callsite → │  CallShape  │  (receiver_type, method, positional/named arg types,
            └─────────────┘   has_block, has_splat, has_double_splat, named_names)
                   │
                   ▼
            ┌──────────────────────────────┐
            │      resolve(CallShape)        │  single entry
            │  ┌────────────────────────┐    │
            │  │ OwnerResolver (was C)  │    │  yields candidate owners (arity-aware
            │  │  arity-aware, no mint  │    │  filtering allowed; never mints names)
            │  └────────────────────────┘    │
            │  ┌────────────────────────┐    │
            │  │ OverloadScorer (was D) │    │  scores overloads → picks best
            │  └────────────────────────┘    │
            └──────────────────────────────┘
                   │
                   ▼
            ┌─────────────┐
            │ Resolution  │  { key : MethodInstanceKey, def : DefNode,
            └─────────────┘    owner : String, returns_via_inheritance : Bool }
                   │
                   ▼
   lower_call binds Call to Resolution.key
                   │
                   ▼
   lower_function_if_needed(Resolution)  ← materializes the SELECTED instance
                   │
                   ▼
   backend emits @<MethodInstanceKey.symbol>; required-arg padding = FAIL-LOUD
```

Key invariants:

1. `base_name` means **overload family only**. It is never a callable
   implementation and never an LLVM symbol.
2. Registration creates stable `DefId`/`MethodDef` entries keyed by a structured
   `MethodInstanceKey`. The mangled string is a *derived* serialization of the
   key, computed in one place.
3. `lower_call` gathers `CallShape` and calls one resolver.
4. `lower_function_if_needed_impl` materializes a *selected* `Resolution`, it does
   not mint identity from a requested string.
5. Identity is established ONCE at registration. Resolution is a pure lookup over
   stable keys — it never generates a new name (this is the refuted-loop guard).

### Proposed structs (additive, no behavior change when first introduced)

```crystal
# Captured at the callsite by lower_call. Pure data.
struct CallShape
  getter receiver_type : TypeRef?      # nil for top-level / bare calls
  getter method        : String        # bare method name, no owner, no suffix
  getter arg_types     : Array(TypeRef) # positional, in order
  getter named_names   : Array(String)? # named-arg names, canonicalized
  getter has_block        : Bool
  getter has_splat        : Bool
  getter has_double_splat : Bool
end

# Stable identity of one concrete callable. Serializes to the mangled symbol.
struct MethodInstanceKey
  getter owner   : String            # e.g. "Foo", "Array(Int32)"
  getter method  : String            # e.g. "hash"
  getter arity   : Int32             # positional param count (post-splat-collapse)
  getter has_block : Bool
  # ... typed-param discriminator, named-only flag, splat flags as needed
  # def to_symbol : String  -> the SINGLE place mangling happens
end

# Output of the resolver. What lower_call / lower_function_if_needed consume.
struct Resolution
  getter key : MethodInstanceKey
  getter def : Adamas::Compiler::Frontend::DefNode
  getter owner_via_inheritance : Bool   # true if resolved to an ancestor
end
```

`MethodInstanceKey#to_symbol` becomes the ONLY caller of the mangling logic now
spread across `function_full_name_for_def` / `mangle_function_name` / the
`$arity`/`_splat`/`_block`/`_named` suffix appenders.

---

## 3. Migration plan (small, safe, ordered commits)

> Progress: **M1 landed** (`ca75ecab`) — structs + `method_instance_symbol`
> (base-mangle parity) + `ADAMAS_MIKEY_ASSERT` guard. **M2 landed** —
> `Resolution` sidecar in `lookup_function_def_for_call` with a verbatim-suffix
> `MethodInstanceKey` that round-trips to the FULL selected name (incl.
> `$arity`/splat/block/named), verified non-vacuous (362 suffixed names) and
> behavior-preserving (combined 31/31, oracle PASS, reducers unchanged). Both are
> env-gated/inert; selection and materialization are untouched.
> **M3a landed** — a `CallShape` sidecar at the front of `lower_call`, gathering
> the source-shape facts (method/block/named/splat) the resolver consumes, with
> an `ADAMAS_CALLSHAPE_ASSERT` gather-invariant check (real Identifier/MemberAccess
> call ⇒ non-empty method name), verified non-vacuous (9106 constructions on the
> direct-hash reducer) and behavior-preserving (combined 31/31, oracle PASS,
> reducers still segfault, NULLPAD blocker intact). NOT consumed: arg_types and
> receiver_type are deferred to M3 proper, and the M2 `resolved_suffix` key is
> verbatim carriage only — neither may drive owner/method/materialization.
> **M3b landed** — a COMPLETE `CallShape` sidecar at the post-arg-lowering point
> in `lower_call` (arg_types + receiver_type now populated, unlike M3a's empty
> front shape), with a committed `CALLSHAPE_SEEN` non-vacuity line and a
> front-vs-complete cross-check (block/splat/named survive lowering). Verified:
> 8677 SEEN constructions on the direct-hash reducer (7623 with a populated
> receiver, 8411 with args), 0 CALLSHAPE_MISMATCH, combined 31/31, oracle PASS,
> reducers still segfault, NULLPAD blocker intact. Still NOT consumed; the bare
> method name is deliberately not cross-checked (legacy rewrites it). Next:
> M0 (needs MIR `had_source_default`, separate commit after review), then full M3
> (route the call name through CallShape once it is proven complete + byte-stable;
> target empty IR diff).
> **M3c landed** — a `CallResolutionInput` sidecar capturing the EXACT lookup-input
> tuple (func_name, arg_count, arg_types, has_block, has_splat, has_named,
> named_names) at the single resolver chokepoint (entry of
> `lookup_function_def_for_call`), the precise input full M3 must reproduce.
> Committed `RESINPUT_SEEN` non-vacuity (67039 on the direct-hash compile),
> round-trip completeness check = 0, `empty_name` invariant = 0, combined 31/31,
> oracle PASS, reducers 139, NULLPAD intact. NOT consumed.
> Two findings for full M3: (1) callsite `**` is folded into args+named by
> `ensure_double_splat_arg` BEFORE the resolver, so has_double_splat is NOT a
> distinct resolver-input axis — it is carried by has_named/named_names; (2)
> `has_named` does NOT imply `named_names` present (534 cases: `to_s(io)` / `.new`
> wrappers pass call_has_named_args=true with nil/empty names) — the
> CallShape→resolver mapping must allow has_named with no explicit names. The M3c
> sidecar is at the resolver entry (not the ~10 individual lower_call lookup
> sites): identical tuple, one stable point, superset coverage.
> **M3d landed** — the resolver now CONSUMES the structured input internally:
> `resolve_call_input(input : CallResolutionInput)` holds the former
> `lookup_function_def_for_call` body (legacy locals destructured from the input);
> the public `lookup_function_def_for_call(func_name, …)` is now a thin wrapper
> that guards, canonicalizes named args, builds the input, and delegates. All ~30
> external callers and the internal recursive calls are unchanged. No CallShape
> mapping yet; behavior-equivalent — diagnostics byte-identical to M3c
> (RESINPUT_SEEN=67039, named_no_names=534), combined 31/31, oracle PASS, reducers
> 139, NULLPAD intact. The stale "a named call must carry names" comment is fixed.
> Next: M3e — one concrete `lower_call` lookup site builds CallResolutionInput from
> its final legacy locals and calls `resolve_call_input` directly (first real
> consumption, controlled blast radius), then broaden; M0 remains a separate axis.
> **M3e landed** — the FIRST real consumption: the main final lookup site in
> `lower_call` (`lookup_function_def_for_call(lookup_name, args.size, …)`, which
> serves the instance/member path including the hash bug) now builds a
> CallResolutionInput from its final legacy locals and calls `resolve_call_input`
> directly, preserving wrapper semantics verbatim (nil for an unreadable name,
> canonicalized named args, exactly one call so the resolver's cache/last-result
> state is not double-mutated). Only this one site converted; cache keys and
> materialization unchanged. Verified: M3E_SITE_SEEN=8672 on the direct-hash
> reducer (406 hash-related — confirms the site serves the hash path), and total
> RESINPUT_SEEN unchanged at 67039 (no double-call, no missed call); RESINPUT/
> CALLSHAPE/MIKEY mismatch=0; combined 31/31; oracle PASS; reducers 139; NULLPAD
> intact. Next: convert the remaining ~9 lower_call lookup sites one/few at a time,
> then the resolver identity can begin to drive materialization (fix path). M0
> stays a separate axis.
> **M3f landed** — two more `lower_call` lookup sites converted to direct
> `resolve_call_input`, same pattern as M3e: the class/module refine
> (`full_method_name`, `call_has_splat`) and the PathNode member-access refine
> (`path_base`, `has_splat`). Wrapper semantics preserved per site; one resolver
> call each; cache keys/materialization unchanged. Both fire on the direct-hash
> reducer (M3F_SITE_SEEN: class_refine=1046, path_refine=200), total RESINPUT_SEEN
> unchanged at 67039 (no double/missed call), all mismatches 0, combined 31/31,
> oracle PASS, reducers 139, NULLPAD intact. Remaining lower_call lookup sites
> (~7: union/module rematch, block fallback, splat-packing helpers, generic
> fallbacks) convert next in small groups, then the resolver identity drives
> materialization (fix path). M0 remains a separate axis.
> **M3g landed** — two LATE-REPAIR sites converted to direct `resolve_call_input`,
> same pattern: the receiver `resolved_base` repair and the final `base_method_name`
> rematch. Full regression green (combined 31/31, oracle PASS, RESINPUT_SEEN
> invariant 67039, all mismatches 0, reducers 139, NULLPAD intact). CAVEAT: both
> sites are COLD — `M3G_SITE_SEEN` fired 0 on the direct-hash reducer AND across
> the whole `combined/*.cr` corpus (they are fallback paths only hit on specific
> resolution-failure scenarios). Non-vacuity is therefore not demonstrable on the
> current corpus; correctness rests on (a) structural identity to the proven
> M3e/M3f conversions, (b) 0 mismatches everywhere, (c) the build type-checking,
> (d) full regression showing no behavior change. Status: COMPLETED, not
> execution-verified. A targeted reducer that forces a receiver-inheritance repair
> / mangled-name rematch would upgrade this to verified; deferred.
> **M3h landed** — the `explicit_new` lookup site converted to direct
> `resolve_call_input`, preserving `prefer_allocator_new_call -> nil`, the literal
> `has_splat=false`, the unreadable-name guard, and canonical named args. Unlike
> M3g this site is HOT: M3H_SITE_SEEN=527 on the direct-hash reducer (Foo.new
> path). Verified: RESINPUT_SEEN invariant 67039; M3E 8672 / M3F class_refine 1046
> unchanged; RESINPUT/CALLSHAPE/MIKEY mismatch=0; combined 31/31; oracle PASS at
> 46.7s. (A first oracle run measured 80.6s at 96% cpu; isolated to external load
> from another session's run_safe busy-poll — a clean re-run returned 46.7s at
> 109% cpu, and the unchanged RESINPUT_SEEN count rules out an algorithmic
> regression.) reducers 139, NULLPAD intact. 6 of 10 lower_call lookup sites now
> route through resolve_call_input. Next: direct_block_entry, then virtual/module
> target loops and splat helpers (denser, isolated commits). M0 separate.
> **M3i landed** — the `direct_block_entry` lookup site (receiver block calls)
> converted to direct `resolve_call_input`, preserving the enclosing
> receiver/block guard, arg_count=call_args.size (NOT args.size), has_block=true,
> has_splat=false, lookup_arg_types exactly, the unreadable-name guard, and
> canonical named args; one call. `lookup_block_function_def_for_call` deliberately
> NOT converted in this commit. Hot: M3I_SITE_SEEN=69 on the direct-hash reducer
> (Indexable(T)#fetch, Slice(UInt8)#rindex). Verified: RESINPUT_SEEN invariant
> 67039; M3E/M3F/M3H counts unchanged; RESINPUT/CALLSHAPE/MIKEY mismatch=0;
> combined 31/31; oracle PASS at 51.9s/107% cpu; reducers 139; NULLPAD intact.
> 7 of 10 lower_call lookup sites now route through resolve_call_input. Next:
> virtual/module target loops (isolated), splat-packing helpers last (they reshape
> args before the resolver call — higher pre/post-pack confusion risk). M0
> separate.

Each commit is independently revertible and gated on the falsifiers in §5. The
ordering front-loads inert scaffolding and instrumentation so behavior changes
come last and minimally.

**M0 — Instrumentation sharpening (no behavior change).**
Split the `NULLPAD_REQUIRED` probe into two classes: (a) `arity_shadow` (callee
has a source-declared REQUIRED param the caller did not supply because resolution
bound a wrong-arity overload) vs (b) `missing_default` (callee param HAS a source
default that was not propagated to MIR `param.default_value`). This makes the §5
falsifier measurable and unblocks the separate `Crystal::Hasher.new` default-prop
bug.
NOTE (implementation constraint, verified by reading llvm_backend.cr:20420): the
backend cannot distinguish the two classes on its own — at the pad site it only
sees `param.default_value == nil`, with no source-level knowledge of whether a
default was declared. M0 therefore needs an UPSTREAM signal: have MIR record a
per-param `had_source_default : Bool` (set when HIR lowers a def whose param had a
default annotation, independent of whether the literal value was propagated).
Then the backend partitions: `had_source_default && default_value.nil?` ⇒
`missing_default`; `!had_source_default` ⇒ `arity_shadow`. Until that field
exists, the scoped §5 falsifier is computed by hand (the
`callee=Crystal$CCHasher$Dnew` lines are `missing_default`; the
`callee=Foo$Hhash param=hasher` / `to_s(io)` lines are `arity_shadow`).
Verify: probe still emits, counts partition cleanly, no IR change.

**M1 — Additive types (no behavior change).**
Introduce `CallShape`, `MethodInstanceKey`, `Resolution` structs (unused or used
only in assertions). Add `MethodInstanceKey#to_symbol` that reproduces the
current mangled string BIT-FOR-BIT (delegate to existing
`function_full_name_for_def`/`mangle_function_name` internally). Verify: combined
+ oracle unchanged; a temporary differential assertion (`to_symbol == legacy
name`) holds across a full hello-world + combined compile.

**M2 — Adapter at the scorer (no behavior change).**
Make `lookup_function_def_for_call` ALSO build and return a `Resolution`
alongside its current `{String, DefNode}` (e.g. via an internal helper or a
parallel return that callers ignore initially). Verify: byte-identical IR for
combined + oracle (the `Resolution` is computed but unused).

**M3 — Route lower_call through CallShape (behavior-preserving refactor).**
`lower_call` constructs a `CallShape` and obtains its `func_name` via
`Resolution.key.to_symbol` instead of ad-hoc string building, but still feeds the
SAME downstream string. Verify: IR diff empty on combined + oracle. This isolates
call-shape gathering without changing selection.

**M4 — Arity-aware OwnerResolver (FIRST real behavior change, tightly scoped).**
Give the owner-resolution feeding `full_name_override` an optional `call_arity`
(nil = legacy arity-blind, preserving the existing cache key and all ~64 callers;
provided = arity-aware skip + arity in cache key). Wire it ONLY at the
member-call resolution that produces the bare override (per
`memory/s2b_hasher_null_self_blocker.md`: ast_to_hir.cr ~68000 / lower_method
override 31164–31170 — re-verify exact lines before editing). A 0-arg `hash`
must skip the 1-required-param `Foo#hash` and resolve to inherited 0-arg
`Object#hash`. Crucially: this SELECTS an existing instance; it mints no new
name. Verify §5 in full, especially the oracle (the refuted loop guard).

**M5 — Ensure the inherited 0-arg monomorph is emitted.**
For a type whose only `hash` is the untyped 1-param method, M4 frees the bare
`Foo#hash` slot; confirm the `Object#hash` monomorph is generated under it (as it
already is for typed-`hash` types like `Array`, `File::Info`). If not, register
it explicitly via the family index. Verify: `h_struct` prints `2`; `f.hash` no
longer segfaults.

**M6 — Secondary: typed-`hash` `.result`-on-Int32 return-type bug.**
Independent of arity: typed `def hash(hasher : Crystal::Hasher)` currently hits
`STUB CALLED: Int32$Hresult` because the chained `@x.hash(hasher)` return is
mistyped as `Int32`. Fix the return-type inference for the hash protocol. Verify
with `/tmp/h_typed.cr`.

**M7 — Default-propagation for `Crystal::Hasher.new` (separate from arity).**
Propagate source defaults of `Crystal::Hasher.new(a, b)` into MIR
`param.default_value` so the M0 `missing_default` class drains. Verify: M0 probe
`missing_default` count for `Crystal$CCHasher$Dnew` → 0.

**M8 — Backend fail-loud.**
Once M4–M7 land and the `arity_shadow` class is empty across combined + oracle +
bootstrap, flip the REQUIRED-with-no-default branch in llvm_backend.cr:20467 from
silent null-pad to a compile-time error/abort. Verify: combined + oracle still
green (proves no remaining silent arity mismatches); bootstrap s2b→s3b.

Only M4–M8 change behavior; M0–M3 are inert scaffolding. Stop and re-plan if any
commit reddens §5.

---

## 4. Smallest first patch

**M0 + M1 bundled is the smallest ambiguity-reducing, zero-behavior-change
patch**, and M1 alone is the canonical "introduce the types" step the task asks
for:

- Add `CallShape`, `MethodInstanceKey`, `Resolution` structs.
- Implement `MethodInstanceKey#to_symbol` delegating to the existing mangler so it
  is byte-identical.
- Make `function_full_name_for_def` internally construct a `MethodInstanceKey`
  and return `key.to_symbol` — i.e. the existing string path is preserved, but the
  identity now flows through the struct. (This is the single behavior-preserving
  "make one existing path use it" the task names.)

This reduces ambiguity (identity now has one structured source of truth) without
touching selection, materialization, or the backend. It is verifiable purely by a
differential check that emitted symbols are unchanged.

---

## 5. Falsifiers (the gate for every behavior-changing commit)

Build: `crystal build src/adamas.cr -o bin/adamas --error-trace`
Run binaries ONLY via `scripts/run_safe.sh <bin> <timeout> <mem_mb>`.

1. **`h_struct`**: `bin/adamas /tmp/h_struct.cr -o /tmp/h_struct` then
   `scripts/run_safe.sh /tmp/h_struct 5 512` must print `2` (currently SEGFAULT).
2. **direct hash**: `/tmp/h_direct_hash.cr` must run without segfault (currently
   SEGFAULT exit 139).
3. **generic-loop guard (refuted-experiment tripwire)**:
   `regression_tests/stage1_split_generic_type_args_runtime_oracle.sh
   <path/to/bin/adamas>` must pass AND compile in seconds (NOT minutes / multi-GB).
   This is the canary for the monomorphization feedback loop.
4. **combined suite**: `regression_tests/run_combined.sh <path/to/bin/adamas> 4`
   must stay 31/31.
5. **NULLPAD population (scoped)**: `ADAMAS_NULLPAD_PROBE=1` on
   `/tmp/h_direct_hash.cr` — the entry
   `callee=Foo$Hhash idx=1/2 param=hasher … caller=__adamas_main` (and the
   inherited-`hash` / `to_s(io)` arity-shadow family) must DISAPPEAR.
   NOTE (adversarial): do NOT use the *total* count as the metric — 144/181 of it
   on the reducer is the unrelated `Crystal::Hasher.new` `missing_default`
   population (drained by M7, not M4). Use the M0 `arity_shadow` class count.

Claim discipline: a fix is VERIFIED only when 1–5 all hold with captured command
output. Until then it is COMPLETED/IN_PROGRESS. `39d2026b` is NOT a fix for this
blocker — it only gates an existing name at the `direct_receiver_method` site and
does not cover the lazy-lowering path that produces the crash.

---

## 6. Open risks / adversarial notes

- **Blast radius of C (`resolve_method_with_inheritance`)**: ~64 callers + an
  arity-free cache key. The optional-`call_arity` approach (legacy default = nil)
  is the only safe way to touch it; re-verify the caller count and cache key
  before editing.
- **Coupling of naming (#1) and resolution (#2)**: per the pinned trace, a
  resolve-only fix hits a symbol-collision wall (the 0-arg `Object#hash` monomorph
  wants the bare slot the untyped method took). M4 and M5 must land together to be
  meaningful.
- **The string is load-bearing in caches**: `function_lookup_cache`,
  `method_inheritance_cache`, `method_index`, `pending_arg_types` are all keyed by
  strings. `MethodInstanceKey` must serialize stably (M1) before any cache can key
  on it; do NOT change cache keys before M2 proves serialization parity.
- **Untyped-param methods are pervasive in stdlib** (`to_s(io)`, `hash(hasher)`,
  `<=>`, custom `==`): any identity-scheme shift is high blast radius and must run
  full regression + a re-bootstrap, not just the reducers.
