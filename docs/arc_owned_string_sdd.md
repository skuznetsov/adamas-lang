# SDD — ARC-owned String (fix "E")

Status: DESIGN (no code yet). Author: bootstrap work, 2026-06-18.
Predecessor: fix "D" (two-heap GC hazard), committed `e635fbc4`.
Convergence trigger: GPT hostile-review recommendation ("stop, write the SDD first")
+ owner directive "по-нормальному" + own option-3. No ABI flip until this doc is
reviewed and a phased plan is accepted.

---

## 1. Problem

Dynamically created `String` objects are never reclaimed at runtime; they leak to
process exit. For a batch compiler this is "merely" unbounded heap growth, but it is
also the surface that produced the #1 s2b startup crash: under Boehm, a live String
held only through a libc container could be collected mid-life (the two-heap hazard,
fixed defensively by D via leak-to-exit). D removed the *crash* by making the atomic
byte-buffer family leak instead of being GC-collected. E is the principled version:
let dynamic Strings be **reference-counted and freed at refcount 0**, so memory is
bounded without relying on Boehm scanning libc interiors.

E is the "do it properly" half of the owner's "fix D, then E" decision.

---

## 2. Verified current state (anchors, not assumptions)

All line numbers are `src/compiler/mir/llvm_backend.cr` unless noted. Verified by
direct read on 2026-06-18 at HEAD (`e635fbc4` + clean tree).

### 2.1 The RC machinery is ALREADY LIVE (Darwin), not a no-op
`__adamas_rc_inc` / `__adamas_rc_dec` (and atomic variants) at 6592–6691 have **two
guards** before touching the refcount, then free-at-0:

1. **null guard** — null ptr → no-op.
2. **raw-base guard** — `%raw = ptr - 8`; `malloc_size(%raw)`; proceed only if
   non-zero. On Darwin `malloc_size` is non-zero **only** when `%raw` is the base of
   a libc malloc/calloc allocation. It is zero for static/`.data` globals, stack
   pointers, and "headerless" runtime objects whose `raw` points *before* their
   allocation base. This is the primary discriminator.
3. **static-sentinel guard** — load `%old` from `%raw`; if `%old >= 2^62`
   (`4611686018427387904`) treat as static and skip. `INT64_MAX`
   (`9223372036854775807`) satisfies this.
4. `rc_dec` decrements; at 0 it calls the destructor (via `@__adamas_dtor_dispatch`,
   9302) then `free(%raw)`.

Non-Darwin builds are still hard no-ops (6696–6713) pending a portable raw-base
discriminator. **E targets Darwin first.**

### 2.2 String is a reference type → rc calls ARE emitted for it
`type_needs_rc?` (hir_to_mir.cr:8024) returns true for `kind.reference?`. String is a
reference type, so `RCIncrement`/`RCDecrement` MIR nodes are already produced for
String-typed values and lowered at `emit_rc_inc`/`emit_rc_dec` (17750/17766).

### 2.3 The header layout is NOT uniform — TWO regimes (CORRECTED 2026-06-18 after GPT review)
An earlier draft of this SDD claimed all dynamic Strings funnel into the one `raw+8`
override. **That is false** (verified by direct read). There are two distinct layouts:

- **Regime A — headered (`[i64 rc-or-sentinel][type_id…][data]`, String ptr = raw+8).**
  `malloc_size(ptr-8) != 0` ⇒ RC-trackable. Producers:
  - ARC/AtomicARC allocs (17708–17713): `__adamas_malloc64(size+8)`, `store i64 1`,
    object = `raw+8`. **Already freed at 0** — true ARC.
  - GC-strategy allocs (17714–17720): same shape, `store i64 INT64_MAX` (sentinel → leak).
  - `String$Dnew$$Pointer$LUInt8$R_Int32_Int32` (10556–10585): alloc `bytesize+21`
    (8 sentinel + 12 header + bytesize + 1 null), `store i64 INT64_MAX` at `%raw`,
    `%str = raw+8`. Other `String$Dnew` arities delegate here (10588–10602).
  - `__adamas_runtime_string_from_cstr` (7635+): same `+21`, same sentinel.

- **Regime B — headerless (`[type_id…][data]`, String ptr = malloc base).**
  `ptr-8` is *before* the malloc base ⇒ `malloc_size(ptr-8) == 0` ⇒ RC **skips** it ⇒
  these leak today and **the sentinel→1 flip does nothing for them**. Verified producers
  all allocate `len+13` (12 header + 1 null, NO 8-byte rc prefix) and `store i32 type_id`
  at offset 0 of the malloc base:
  - `__adamas_string_byte_slice` (7502/7519), `__adamas_string_substring` (7607),
    `__adamas_create_substring` (8143/8145), `__adamas_string_concat` (8931),
    `__adamas_string_interpolate` (8977), `__adamas_string_repeat` (9100),
    `__adamas_string_gsub` (7347) / `_gsub_char` (7457) / `_gsub_regex` (9605),
    `__adamas_string_split_string` segments (8162+).
  - **`String::Builder#to_s` (stdlib builder.cr:100–115):** returns `@buffer.as(String)`
    where `@buffer = GC.malloc_atomic(...)` (libc post-D, header at offset 0, NO rc prefix).
    Builder is STDLIB (cannot be modified); in prelude mode this stdlib body runs (compiler
    only overrides the no-prelude stub at 3959). So `String.build` results are Regime B.

**Implication:** the mechanical E change is NOT two `store` edits. The full dynamic-String
producer surface must be migrated to a single headered layout (Regime A) — "string
allocation unification" — and the Builder path needs a dedicated decision (it is stdlib).

### 2.4 Static String literals are doubly protected
`.data` constant globals (5884–5922, 6519–6521) embed `INT64_MAX` at offset 0 and the
String pointer aliases past it (`+8`). They are skipped by BOTH guards: `malloc_size`
of a non-heap pointer is 0 **and** the value is the sentinel. Literals are not
freeable regardless of E.

### 2.5 String has no reference fields → no String destructor needed
`__adamas_dtor_dispatch` (9302) switches on type_id and rc_dec's reference fields.
String's bytes are inline; there are no ref fields to cascade. Freeing a String =
`free(raw)`. (Confirm String's type_id is not in `@dtor_type_ids`, so `destructor`
arg is whatever the call site passes — the free path tolerates a null/absent dtor.)

### 2.6 Interaction with D (already shipped)
D redirected `GC.malloc_atomic → __adamas_malloc64` (libc) and `GC.realloc →
__adamas_gc_aware_realloc` (GC_base-aware) **globally** (the `emit_extern_call` case at
~22619, not String-specific). Regime-A Strings allocate `raw` then return `raw+8`, so
`malloc_size(raw) != 0` and they are RC-eligible once the sentinel is replaced. Regime-B
Strings and Builder buffers return the malloc base directly, so `malloc_size(ptr-8) == 0`
and they are RC-*inert*. **Consequence for E:** the fix cannot live at the generic atomic
allocator (D shares it with Builder/IO/other raw byte buffers — changing it to "return
raw+8 headered" would corrupt those non-String users). E must be **String-construction-
specific**, not allocator-level.

### 2.7 Headered allocation ≠ reclamation — most producers have NO drop path (VERIFIED 2026-06-18, GPT review #2)
Migrating a producer to the headered Regime-A layout (§4) makes its result *RC-eligible*
but does NOT make it *reclaimed*. Reclamation needs an `rc_dec` to actually fire at the
end of the value's owning scope, and that drop site is emitted by a separate mechanism:

- The per-block ARC cleanup `@block_arc_temps` (hir_to_mir.cr:2207–2219, verified) tracks
  a value for drop **only if** `hir_value.is_a?(HIR::Call)` **and**
  `callee_returns_owned?(method_name)` (`@owned_return_funcs`, hir_to_mir.cr:166/2548).
- **String interpolation and 2-part concat bypass this entirely.** `"#{x}"` lowers in
  ast_to_hir to `HIR::StringInterpolation`, then to a non-Call `MIR::StringInterpolation`
  node (hir_to_mir.cr:7532, verified). The LLVM backend's `emit_string_interpolation`
  (llvm_backend.cr:25426–25700, verified) emits the helper calls *directly*
  (`__adamas_int_to_string`, `__adamas_char_to_string`, `__adamas_string_concat` at 25690,
  `__adamas_string_interpolate` at 25699) — these are NOT `HIR::Call` nodes, so
  `@block_arc_temps` never sees them. Both the intermediate `.conv#{idx}` temporaries AND
  the final concat/interpolate result are fresh String temporaries **with no owner and no
  drop site.** Even fully headerized, they would still leak.

**Implication for E:** "freeable" is a two-part property — (layout: headered) AND
(ownership: a drop site exists). E-R0 must classify producers along BOTH axes (§8). A new
cleanup path for `MIR::StringInterpolation` results (and their intermediate conversion
temporaries) is required, OR these are explicitly admitted as a leaking subset. This is
tracked as §11.7 and the dedicated falsifier E-R14.

### 2.8 The drop-path gap is broad, not interpolation-specific (VERIFIED for ExternCall + StringInterpolation; String.new pending D1)
The E-R0 census (`docs/arc_owned_string_er0_census.md`) extended §2.7's interpolation
finding across the producer surface: it is the general case, not the exception. **Every
producer the census verified — all Regime-B `ExternCall` producers + the
`StringInterpolation` family — has no scope-end drop site.** The only scope-end `rc_dec` is
`builder.rc_dec` (hir_to_mir.cr:2076) draining `@block_arc_temps`, gated on `HIR::Call`. But
these producers lower to **`HIR::ExternCall`** (byte_slice, substring, gsub/_char/_regex,
repeat, split, `String * Int` — verified at ast_to_hir.cr 59234/72865/72926/72971–72988/
87314/87679) or **`MIR::StringInterpolation`** (interpolation + 2-part concat). Neither is an
`HIR::Call`, so none are tracked. Container stores *do* `rc_inc` (FieldSet 3120, IndexSet/
array 3490, ctor-arg 2443), so stored Strings are retained — but the producer temporaries are
never dropped. **D1 RESOLVED empirically (2026-06-18):** a `@owned_return_funcs` membership
dump over a string-heavy prelude compile (68 members) contains ZERO byte-buffer producers
(0 hits for `Dnew`/`byte_slice`/`substring`/`gsub`/`string_concat`/`interpolat`/`repeat`/
`split`/`_to_string`); the only String-typed members are the high-level `String.new$String`
/ `String::Builder.new*`, which are disjoint from the producer surface. So the drop-path gap
over the byte-buffer producers (census items #1–#20) is confirmed total, not just inferred.

**Consequence:** E is two independent bodies of work, and drop-site emission is the larger:
(1) layout unification (§4, ~18 producers, the cheap part); (2) **drop-site emission** —
widen the scope-end `rc_dec` mechanism beyond `HIR::Call` to cover owned String `ExternCall`
/ `StringInterpolation` results (the bulk + the correctness risk); (3) retain/release
balancing (§7). Without (2), (1) frees nothing. Tracked as §11.7 (now generalized) + E-R14.

### Conclusion of §2 (the central thesis — REVISED 2026-06-18 after GPT review)
**E is ABI-MODERATE (not trivial) and ownership-correctness-hard.**
- *Not* trivial at the ABI: the dynamic-String producer surface is split across two
  layout regimes (§2.3). Regime-B producers (byte_slice/substring/concat/interpolate/
  repeat/gsub/split + `String::Builder#to_s`) are headerless and RC-inert; a sentinel→1
  flip does nothing for them. Making all dynamic Strings reclaimable requires migrating
  every producer to a single headered layout ("string allocation unification"), and the
  Builder path is stdlib (cannot be edited) so it needs a dedicated mechanism or an
  explicit admitted-leak decision.
- *Not* uniformly reclaimable even once headered: a headered layout is necessary but not
  sufficient (§2.7). Hot producers — `StringInterpolation` and 2-part `concat` — emit their
  results outside the `HIR::Call` owned-return cleanup, so they have **no drop site** and
  would leak even fully headerized. Reclamation = (headered layout) AND (a drop site exists).
- *Hard* at correctness: once Strings are freeable, the already-emitted rc_inc/rc_dec
  **activate**, exposing every unbalanced retain/release (invisible today because strings
  leak) as a use-after-free or double-free across container store/evict, call-return,
  slice/to_unsafe alias, and Builder ownership transfer.

The first task (E-R0, §8) is therefore a **complete producer census** classifying every
dynamic-String constructor along TWO axes — layout (headered-freeable / headerless-leaking
/ borrow-or-literal) AND ownership/drop-path (fresh +1 with a cleanup site / borrowed
passthrough needing rc_inc / no cleanup path yet) — before any flip.

---

## 3. Goals / Non-goals

### Goals
- Dynamic Strings are freed when their last owning reference is dropped (Darwin).
- No regression in the 160/160 + 31/31 suites; no new s2b startup crash; s2b builds.
- Bounded heap on a long compile (measurable RSS drop vs leak-to-exit on a string-
  heavy workload).
- Zero behavior change for static String literals.

### Non-goals (this iteration)
- Portable (non-Darwin) ARC. Stays no-op until a raw-base discriminator exists.
- Reclaiming other GC-strategy objects (Hasher, Mutex, Fiber lists, cyclic types).
- Cycle collection. ARC cannot reclaim cycles; Strings cannot form cycles, so this is
  acceptable for E's scope.
- Changing D's allocator redirect or the GC model. E stays inside the gated
  GC/allocator boundary the owner authorized.

---

## 4. Admitted surface (what E changes) — string-construction unification

E introduces ONE headered-allocation helper and routes every freeable-String producer
through it; the sentinel→refcount choice becomes a parameter of that helper.

- **New `__adamas_alloc_string(i32 %bytesize, i32 %size, i32 %tid, i64 %rc) -> ptr`**:
  allocates `bytesize + 8 (rc) + 12 (header) + 1 (null)` via `__adamas_malloc64`,
  `store i64 %rc` at `%raw`, writes type_id/bytesize/size at `raw+8`, returns `raw+8`.
  Literals pass `%rc = INT64_MAX`; freeable dynamic strings pass `%rc = 1`.
- **Regime-A producers** (already `raw+8`): swap the inline `store i64 INT64_MAX` for the
  helper (or for `store i64 1`): `String$Dnew$$Pointer$LUInt8$R_Int32_Int32` (10572),
  `__adamas_runtime_string_from_cstr` (7647). Delegating arities inherit automatically.
- **Regime-B producers** (currently headerless `+13`): migrate to the helper so they
  return `raw+8` with rc=1 — `__adamas_string_byte_slice` (7502),
  `__adamas_string_substring` (7607), `__adamas_create_substring` (8143),
  `__adamas_string_concat` (8931), `__adamas_string_interpolate` (8977),
  `__adamas_string_repeat` (9100), `__adamas_string_gsub`/`_char`/`_regex` (7347/7457/9605),
  `__adamas_string_split_string` segments (8162+). **Caution:** `concat` returns an input
  (`ret %b` at 8941 / `ret %a` at 8946) when one side is **null** (`%a_null`/`%b_null`,
  verified 8933–8946) — that is a borrow passthrough; it must `rc_inc` the returned input
  (it is handing out a new owning reference), not allocate. (The branch is keyed on null,
  not on empty-string content.)
- **Interpolation / concat result drop site (§2.7):** migrating these producers to the
  helper makes the result headered but still *ownerless* — `emit_string_interpolation`
  (llvm_backend.cr:25426) emits the helper calls directly, so neither the `.conv#{idx}`
  intermediate temporaries nor the final concat/interpolate result are tracked by
  `@block_arc_temps`. E must additionally emit an `rc_dec` for `MIR::StringInterpolation`
  results (and their conversion temporaries) at end of owning scope — a source-shape-keyed
  cleanup, not the `__adamas_alloc_string` migration. Tracked as §11.7 / E-R14.
- **`String::Builder#to_s` (stdlib, immutable):** cannot be edited in place. Note the
  Builder's own `@buffer : Pointer(UInt8)` (builder.cr:9) is **NOT auto-freed** — the
  ARC destructor only rc_dec's *reference/array/all-ref-union* fields (`has_ref_field`
  gate, llvm_backend.cr:9256–9264, verified), and `Pointer(UInt8)` is none of those. So
  the earlier "the original `@buffer` is freed by Builder's own drop" claim is FALSE.
  Decision fork (preferred HYPOTHESIS, not accepted design — falsify in P1, see §11.6):
  - **(a1)** compiler override of `String$CCBuilder$Hto_s` that allocates a headered String
    via the helper, memcpy's `@buffer`'s bytes, AND explicitly `free`s `@buffer` (a one-time
    finalize copy + free; acceptable under zero-copy as the ownership boundary). Preferred:
    `String.build` is a dominant compiler-internal producer, so reclaiming it serves the RSS
    goal, and the explicit free avoids leaking the (now-orphaned) original buffer.
  - **(a2)** same override + copy, but **admit the original `@buffer` leaks** (no explicit
    free). Simpler; bounded leak = one buffer per `String.build`.
  - **(b)** **admit Builder strings as a leaking subset** in E-v1 (keep sentinel/headerless;
    not reclaimed). Touches no Builder path at all.

## 5. Rejected surface (what E must NOT touch)

- Static `.data` String literals (5884–5922, 6519–6521): keep `INT64_MAX`.
- `@.str.empty` and other shared singleton literals returned by `ret_empty` paths in
  the overrides: these return a **literal**, never a fresh allocation — safe, no rc.
- Value-type (struct) GC allocs (2727–2731): not reference-counted; untouched.
- Cyclic / FFI-exposed / generic-GC objects (Hasher, Mutex, Fiber lists): keep
  sentinel. E is String-only.
- Non-Darwin rc bodies: stay no-op.

---

## 6. Allocation / realloc ABI

- **Allocation returns `raw+8`.** Already true for String overrides and ARC allocs.
  The object pointer the program sees is `raw+8`; `raw` (the libc base) holds the rc.
- **Free frees `raw` (= ptr-8).** Already true in rc_dec (`free(%raw)`).
- **Realloc must realloc `raw`, not the object pointer**, and return `new_base+8`.
  Today no migrated String-object realloc path exists: growth happens on a plain byte
  buffer inside `String::Builder`. `Builder#to_s` does NOT copy — it returns
  `@buffer.as(String)` (builder.cr:114), i.e. it adopts the grown buffer in place. So if
  E headerizes Builder via override (§4 option a1/a2), that override is the only place a
  Builder buffer becomes a headered String, and it copies once at finalize (a1 also frees
  the orphaned `@buffer`, which is NOT auto-freed by the destructor — see §4/§11.6).
  **Constraint for E:** do not introduce in-place String-object growth without a
  raw-based realloc helper; if ever needed, add `__adamas_string_realloc(obj,size)`
  that reallocs `obj-8` and returns `base+8`. (Out of scope now; documented so a future
  change doesn't silently realloc the object pointer.)
- **`gc_aware_realloc` interaction:** the Builder byte buffer is libc-malloc'd (post-D),
  so `GC_base` is null → libc realloc. Correct, unchanged by E.

---

## 7. RC ownership rules (the hard core)

Reference-counting discipline that must hold once Strings are freeable. Each is a
falsifier target in §8.

- **Borrow vs own.** A value that is only *read* through (no stored, no returned, no
  escaped) must not be retained/released. A value that is *stored into a container,
  field, or global*, or *returned*, transfers/retains an owning reference.
- **Container store (`Hash`/`Array`/`Set` of String):** storing a String must
  `rc_inc` (the container now owns a reference); removing/overwriting/clearing must
  `rc_dec` the evicted String. **Key risk:** if the container is implemented over
  `Pointer(String)` + `PointerStore`, the store may bypass the per-value rc_inc.
- **Call return.** A function returning a freshly-allocated String hands ownership to
  the caller (rc already 1; caller's drop releases). A function returning a *borrowed*
  String (e.g. returns a field) must `rc_inc` before returning so the caller's drop is
  balanced.
- **Slices / `to_unsafe` / `to_slice`:** these alias *into* the String's data; they do
  NOT own and must NOT rc_dec the String. Risk: a Slice outliving its String → UAF.
  E must confirm Slice-from-String does not free the backing String early.
- **`String::Builder#to_s` ownership transfer (CORRECTED twice):** `to_s` does NOT copy —
  it returns `@buffer.as(String)` (builder.cr:114), adopting the libc byte buffer in place
  (headerless, Regime B). The Builder's `@buffer : Pointer(UInt8)` is **NOT** freed by the
  ARC destructor (it is not a ref/array field; `has_ref_field` gate at llvm_backend.cr:9256).
  So under option (a1) the override must copy `@buffer` into a headered String (rc 1) AND
  explicitly `free(@buffer)`; under (a2) the original `@buffer` is admitted-leaked; under
  (b) Builder strings stay headerless and leak. There is no implicit "Builder's own drop"
  to rely on. Confirm the chosen option's drop path with E-R7.
- **`StringInterpolation` / 2-part `concat` results (NEW, §2.7):** these are emitted by
  `emit_string_interpolation` outside the `HIR::Call` cleanup, so they currently have NO
  owner. Once freeable, E must emit an `rc_dec` at end of owning scope for both the final
  result and the intermediate `.conv` conversion temporaries; otherwise they leak even when
  headered. Falsifier E-R14.
- **`concat`/passthrough returns:** `__adamas_string_concat` returns an *input* string
  when the other side is **null** (`ret %b` at 8941 / `ret %a` at 8946, keyed on
  `%a_null`/`%b_null`). That hands out a new owning reference to an existing String → it
  must `rc_inc` the returned input, not assume rc=1 from a fresh alloc. Any helper that may
  return an input rather than a fresh allocation needs this.
- **`WeakRef(String)`:** must NOT retain. Currently strings never free, so weak refs
  are trivially always-valid; once freeable, WeakRef must observe nulling. (May be
  acceptable to declare WeakRef-of-String unsupported in E scope if no s2b path uses
  it — verify.)
- **Globals / class vars holding String:** retained for program lifetime; their rc
  never reaches 0 (or is set to sentinel). Confirm cache strings (e.g.
  `@normalize_decl_cache`, the exact string the watchpoint caught in the D
  investigation) are owned by a live container the whole run.

---

## 8. Reducer / falsifier matrix

Two classes, kept separate (GPT review #4): **baseline-correctness** reducers must pass
BOTH at baseline-D and under the gate (they assert no crash / correct output, never RSS
bounds); **gated-reclaim** reducers are only meaningful with the gate ON (they assert
freeing/RSS, which by construction CANNOT hold under leak-to-exit). Each reducer prints
its invariant to STDERR and runs via `scripts/run_safe.sh`.

### E-R0 — producer census (PRODUCED 2026-06-18 → `docs/arc_owned_string_er0_census.md`)
A document/table (not a runtime reducer) enumerating EVERY dynamic-String constructor in
`src/compiler/mir/llvm_backend.cr` + stdlib paths, classified along **two axes**. The full
census now lives in `docs/arc_owned_string_er0_census.md`; its central verified finding is
that the drop-path gap is TOTAL (§2.8), not interpolation-specific. Axes: 

- **Layout:** `headered-freeable (Regime A)` / `headerless-leaking (Regime B)` /
  `borrow-or-literal`.
- **Ownership / drop-path:** `fresh +1 with a cleanup site` (result is an `HIR::Call` to an
  `@owned_return_funcs` member → tracked by `@block_arc_temps`, hir_to_mir.cr:2211) /
  `borrowed passthrough → needs rc_inc on the returned input` (e.g. concat null branch) /
  `no cleanup path yet` (emitted outside `HIR::Call`, e.g. `MIR::StringInterpolation` and
  its `.conv` temporaries → needs a new source-shape-keyed drop site, §2.7/§11.7).

Seed list (verified 2026-06-18): **Layout** — Regime A = `String$Dnew$$…Int32_Int32`
(10556), `runtime_string_from_cstr` (7635). Regime B = byte_slice (7502), substring (7607),
create_substring (8143), concat (8931, NB null passthrough), interpolate (8977), repeat
(9100), gsub/_char/_regex (7347/7457/9605), split segments (8162), `String::Builder#to_s`
(stdlib 100–115). Borrow/literal = `@.str.*` globals, `ret_empty` paths. **Ownership** —
`no cleanup path yet` = interpolation/2-part-concat results + `.conv` temps from
`emit_string_interpolation` (llvm_backend.cr:25426–25700); `borrowed passthrough` = concat
null branch (8941/8946); the rest need per-producer audit of whether the result flows
through an `@owned_return_funcs` `HIR::Call`. E-R0 is the gate on whether §4's unification
list AND the §11.7 cleanup set are complete; an unclassified producer (on either axis)
blocks the flip.

### Baseline-correctness reducers (pass at baseline AND under gate)

**Status (2026-06-18): PRODUCED + PASS at baseline-D.** E-R2..E-R10 ship as the single
one-compile reducer `regression_tests/arc_owned_string_baseline_repro.sh` (labeled cases,
full-line assert pinpoints the diverging ID); E-R11 ships as
`regression_tests/arc_owned_string_er11_s2b_repro.sh` (bounded proxies always run: `x=1`
links clean + string-churn producer mix; the full `src/adamas.cr` self-build is opt-in via
`ADAMAS_ER11_FULL=1` — heavy/multi-GB, shared-machine guard). The full opt-in path was exercised
2026-06-18: `bin/adamas` self-builds s2b, s2b builds `x=1`, and the result runs clean exit 0.
Both reducers pass against `bin/adamas` (baseline-D). These are now the P2
regression guard: any drop-site that frees too early (E-R4/R5/R6) or double-frees a
passthrough/literal (E-R8/R9) will flip a locked assertion. (The cheap `x=1` link gate also
overlaps `gc_aware_realloc_gating_repro.sh`, which additionally asserts the wrapper emission.)

| ID | Scenario | Invariant | Hazard probed |
|---|---|---|---|
| E-R2 | `Hash(String,Int32)` insert/overwrite/delete | values correct after churn | container store/evict rc |
| E-R3 | `Array(String)` push/pop/clear | elements correct; no UAF | array store/evict rc |
| E-R4 | return fresh String from fn, use after | content intact | call-return ownership |
| E-R5 | return field String from fn, store, drop original owner | content intact | borrowed-return retain |
| E-R6 | `to_slice`/`to_unsafe`, use slice after String var drop | bytes intact | slice-alias no early free |
| E-R7 | `String.build`, use result, drop; also single-use/abort path | content intact; under (a1) no double-free of `@buffer` AND no orphaned-buffer leak AND no live alias to `@buffer` after `to_s` | Builder#to_s transfer + `@buffer` ownership |
| E-R8 | literal passed around, stored, dropped | correct; no crash | literal not corrupted |
| E-R9 | `String + String` concat chains (incl. concat w/ empty) | correct | intermediate/passthrough rc |
| E-R10 | string in class var / global, read late | intact whole run | global ownership |
| E-R11 | s2b reproducer (`bin/adamas` building `x=1`, then `src/adamas.cr`) | clean exit; builds | original crash, under freeable strings |

### Gated-reclaim reducers (meaningful only with gate ON)
| ID | Scenario | Invariant | Hazard probed |
|---|---|---|---|
| E-R1 | allocate N strings in a loop, drop each | RSS bounded (vs unbounded at baseline) | basic free-at-0 |
| E-R13 | string-heavy compile, measure peak RSS gate ON vs OFF | RSS(ON) < RSS(OFF) | reclamation actually fires |
| E-R12 | lldb hw watchpoint on the D-era live cache string | no premature free | E doesn't reintroduce two-heap symptom |
| E-R14 | interpolation `"#{i}-#{j}"` / 2-part `"a" + b` in a loop, drop each | RSS bounded | §2.7 ownerless-temp drop site fires |

Acceptance gate: E-R0 complete + all baseline reducers pass at baseline AND gate-ON +
all gated-reclaim reducers pass gate-ON + full 160/160 + 31/31 + s2b (E-R11) + E-R12.

---

## 9. Phased rollout (gated, revertible)

Each phase is one commit, suite-gated, individually revertible.

- **P0 (this doc).** SDD reviewed/accepted. No code.
- **P1 — census + baseline reducers.** (a) ✅ E-R0 produced (the two-axis producer census,
  §8 → `docs/arc_owned_string_er0_census.md`; D1 owned-return audit RESOLVED empirically).
  §11.7 cleanup-path route chosen (source-shape whitelist + backend-local `.conv` cleanup);
  §11.6 Builder decision held as preferred hypothesis (a1 = copy+free) — its falsifier (E-R7)
  can only be *exercised* gate-ON (at baseline-D nothing frees), so the final a1/a2/b lock is
  a P2 measurement. (b) ✅ Baseline-correctness reducers E-R2..E-R11 landed and PASS at
  baseline-D (`regression_tests/arc_owned_string_baseline_repro.sh` +
  `arc_owned_string_er11_s2b_repro.sh`). The flip is now falsifiable with a bisect baseline.
  (Census + test addition — SAFE, no ABI change.) Gated-reclaim reducers
  (E-R1/E-R12/E-R13/E-R14) are written here but only asserted in P2+.
- **P2 — unify allocation + flip behind an env gate.** Add `__adamas_alloc_string` (§4)
  and an `ADAMAS_ARC_STRING=1` gate that (i) routes every census producer through it with
  `rc=1` and (ii) applies the Builder decision. Default OFF. Run the full matrix gate-ON;
  triage failures (each localizes a missing retain/release per §7). Iterate gate-ON only.
- **P3 — fix retain/release gaps** found in P2, one logical fix per commit, each with
  its reducer flipping FAIL→PASS. This is the bulk of E.
- **P4 — default ON.** When all reducers + suite + s2b pass with the gate ON, make ON
  the default; keep the env var as an escape hatch for one release.
- **P5 — remove the gate** once stable across a stage2/stage3 cycle.

Rationale for the env gate: leak-to-exit (D) is a correct fallback, so E can be
developed incrementally without ever shipping a half-flipped, double-free-prone
compiler. The gate makes every step revertible by an env var, not a rebuild.

---

## 10. Risk register

| Risk | Likelihood | Detection | Mitigation |
|---|---|---|---|
| Missing rc_inc on container store → premature free → UAF | HIGH | E-R2/E-R3 crash | P3 add retain at store site |
| Double rc_dec (evict + scope) → double free → malloc abort | MED | E-R2 abort | balance evict vs drop |
| Slice outlives String → UAF | MED | E-R6 | slice borrows, no rc_dec of backing |
| Literal accidentally flipped → free of `.data` | LOW | E-R8 + crash | §5 keeps sentinel; malloc_size guard also blocks |
| Builder buffer double-free OR orphaned-buffer leak | MED | E-R7 | §11.6 a1 copies+frees; confirm no alias |
| Interpolation/concat temps leak even when headered (no drop site) | HIGH | E-R14 RSS unbounded | §11.7 source-shape-keyed rc_dec |
| Non-Darwin build silently leaks (no-op rc) | EXPECTED | n/a | documented non-goal |
| Stage2/3 divergence (s2b behaves unlike stage1) | MED | E-R11 + s2b build | gate lets s2b stay OFF until proven |

Rollback: set `ADAMAS_ARC_STRING=0` (P2–P4) or revert the single flip commit. D's
leak-to-exit remains the safe floor.

---

## 11. Open questions (resolve before/within P1)

1. **"P2 = two store edits" — REFUTED 2026-06-18 (GPT review #1, verified by direct read).**
   The earlier claim that all dynamic Strings funnel into the one `raw+8` override is
   FALSE. There are two layout regimes (§2.3): Regime-A producers are headered (`raw+8`,
   2 sites), but the bulk — byte_slice/substring/create_substring/concat/interpolate/
   repeat/gsub/split + `String::Builder#to_s` — are **headerless** (`+13`, String ptr =
   malloc base), so `malloc_size(ptr-8)==0` and a sentinel→1 flip does NOTHING for them.
   `select_memory_strategy` still does not govern String objects (they are not MIR
   `Allocate` nodes), so the fix is NOT a strategy change — but it IS a full producer
   census + migration to one headered helper (§4), not two stores. RESOLVED-sub: the
   generic GC `Allocate` path at 17719 is not a String producer; safe to ignore.
2. **Does any s2b path use `WeakRef(String)` or String finalizers?** If not, declare
   them out of scope for E (assert with a grep over `src/`).
3. **Are there String-typed values whose rc calls are currently SKIPPED** by the
   `llvm_type == "ptr"` guard in emit_rc_inc/dec (17754, 17770) — e.g. String inside a
   union represented as scalar? Those would not be retained/released and could leak or
   UAF inconsistently. Enumerate.
4. **`@dtor_type_ids` membership of String. — RESOLVED 2026-06-18.** A type is added to
   `@dtor_type_ids` only if `has_ref_field` (9255–9264). String has no reference fields
   (inline bytes), so it is never registered. Freeing a String passes
   `@__adamas_dtor_dispatch`, which reads String's type_id, finds no case, falls to
   `no_dtor` → `ret`, then `free(raw)`. Free is clean; no spurious destructor.
5. **GMP / BigInt strings and other `GC.malloc` (scanned) producers** — confirm none
   produce a String object that would now be freed while a scanned-heap holder expects
   it alive. (Low: BigInt uses its own limbs, not String.)
6. **Builder headerization decision — OPEN (GPT review #2; resolve in P1).** `String::
   Builder#to_s` is stdlib and returns `@buffer.as(String)` in place (cannot edit stdlib).
   Its `@buffer : Pointer(UInt8)` is NOT auto-freed (not a ref/array field; `has_ref_field`
   gate, llvm_backend.cr:9256, verified) — so any "freed by Builder's own drop" assumption
   is false. Choose: **(a1)** compiler override of `String$CCBuilder$Hto_s` that copies
   `@buffer` into a headered String AND explicitly `free`s `@buffer` (preferred HYPOTHESIS,
   not accepted design — `String.build` is a dominant compiler-internal producer, so leaving
   it leaking undercuts the RSS goal; falsify with E-R7 before adopting); **(a2)** copy +
   admit the orphaned `@buffer` leaks (one buffer per build); **(b)** admit Builder strings
   as a leaking subset in E-v1 (touch no Builder path). Decision drives whether P2 touches
   Builder at all. **Falsifier before locking (a1):** E-R7 must show no double-free and no
   UAF of `@buffer` (confirm nothing else aliases it after `to_s`).
7. **Producer drop-path mechanism — OPEN, and bigger than first thought (GPT review #2/#3 +
   E-R0 census; §2.7/§2.8).** Originally scoped to interpolation; the census (§2.8) showed
   the gap is broad — every byte-buffer producer (census #1–#20) lacks a scope-end drop site
   (D1 confirmed: 0 byte-buffer producers in the `@owned_return_funcs` dump), because they
   lower to `HIR::ExternCall` or `MIR::StringInterpolation`, while the only drop site
   (`@block_arc_temps` drain, hir_to_mir.cr:2076) is gated on `HIR::Call`. The already-tracked
   `String.new$String` / `String::Builder.new*` are disjoint (D1) — the whitelist is additive
   and must verify non-overlap in P2. Mechanism (route chosen, GPT review #3):
   - **(a) — PREFERRED — source-shape-keyed whitelist.** Widen the tracker at
     hir_to_mir.cr:2211 to enroll owned String `HIR::ExternCall` and `HIR::StringInterpolation`
     *final* results, but ONLY for the producers whitelisted in E-R0 (NOT by type), reusing
     the existing cross-block / moved-value exclusions. A whitelist is mandatory because
     literal / borrowed / passthrough branches (e.g. `bool_to_string` returning a `.data`
     literal, concat's null `ret %a/%b`) must NOT be rc_dec'd.
   - **(a-supplement) — local `.conv` cleanup inside `emit_string_interpolation`.** The
     intermediate conversion temporaries (`__adamas_int_to_string`, `_char_to_string`,
     `_array_*_to_string`, …) do NOT exist as HIR/MIR values — they are emitted inline by the
     backend (llvm_backend.cr:25426–25700), so widening `@block_arc_temps` cannot see them.
     They need a backend-local `rc_dec` after the final interpolate/concat consumes them,
     respecting the literal/`@.str.empty` branches that produce no fresh alloc.
   - **(b) — REJECTED — type-only "parallel String drop pass".** Dropping by result-type =
     String cannot distinguish fresh-alloc from literal/borrowed/passthrough → double-free.
     Kept only as a named anti-pattern.
   - **(c) — explicit admitted leak** of a named subset, ONLY if E-v1 scope is cut for volume;
     must be documented, not implicit.
   Falsifier E-R14. Independent of the §4 `__adamas_alloc_string` migration: layout and
   drop-path are separate axes (§2.7/§2.8). **Resolve the whitelist with the D1 empirical
   owned-return dump first** (E-R0 census, "Open audits").

---

## 12. Acceptance criteria (definition of done for E)

- E-R0 census complete (every dynamic-String producer classified on BOTH axes —
  layout and ownership/drop-path); §11.6 (Builder a1/a2/b) and §11.7 (interpolation
  cleanup) decided.
- All baseline-correctness reducers (E-R2..E-R11) PASS at baseline AND gate-ON.
- All gated-reclaim reducers (E-R1/E-R12/E-R13/E-R14) PASS gate-ON.
- `scripts/run_all_specs.sh` regression: 160/160 originals + 31/31 combined hold.
- s2b builds and runs (E-R11); lldb watchpoint shows no premature free (E-R12).
- Measurable RSS reduction on a string-heavy workload vs leak-to-exit (bounded heap).
- One env-gated, phase-by-phase commit trail; each commit individually revertible.
- Memory/LANDMARKS updated with the verified §2 two-regime anchors and the
  ABI-moderate / correctness-hard thesis.

Status remains DESIGN until the E-R0 two-axis census exists, §11.6 (Builder) and §11.7
(interpolation cleanup) are decided, and the baseline-correctness reducers are landed and
green at baseline.
