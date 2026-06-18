# E-R0 — Dynamic-String producer census (fix "E", P1 first artifact)

Status: CENSUS (verified by direct read, 2026-06-18, HEAD `e635fbc4` + clean tree).
Companion to `docs/arc_owned_string_sdd.md`. This is the gate on §4's unification list
and the §11.7 drop-path set: an unclassified producer (on EITHER axis) blocks the flip.

## Method

Each dynamic-String constructor is classified along two independent axes (SDD §2.7):

1. **Layout** — where the String pointer sits relative to its malloc base, which decides
   RC-eligibility via the `malloc_size(ptr-8) != 0` raw-base guard in `__adamas_rc_dec`
   (llvm_backend.cr:6592–6691):
   - **Regime A (headered):** alloc `... + 8`, `store i64 rc-or-sentinel` at `%raw`,
     object = `raw+8`. `malloc_size(raw) != 0` ⇒ RC-eligible once rc≠sentinel.
   - **Regime B (headerless):** alloc `len + 13` (12-byte header + 1 null, NO rc prefix),
     `store i32 type_id` at offset 0, object = malloc base. `malloc_size(base-8) == 0`
     ⇒ RC **skips** it ⇒ leaks; a sentinel→1 flip does nothing.
   - **Borrow/literal:** returns an existing String or a `.data` global; never a fresh alloc.

2. **Ownership / drop-path** — whether a scope-end `rc_dec` is ever emitted for the result.
   The ONLY scope-end drop site is `builder.rc_dec(mir_id)` at hir_to_mir.cr:2076, draining
   `@block_arc_temps`. Entries are added at hir_to_mir.cr:2211–2215 **only when**
   `hir_value.is_a?(HIR::Call)` AND `callee_returns_owned?` (`@owned_return_funcs`).
   `@owned_return_funcs` is seeded by `returns_allocated_value?` (2622), which requires the
   method's return to trace to an `HIR::Allocate && !is_value_type`.
   - **fresh +1 with cleanup site:** result is an `HIR::Call` to an `@owned_return_funcs`
     member → tracked → dropped at scope end.
   - **borrowed passthrough:** helper may return one of its inputs → needs `rc_inc` on the
     returned input, not a fresh-alloc assumption.
   - **no cleanup path yet:** result is emitted as `ExternCall` or `MIR::StringInterpolation`
     (NOT an `HIR::Call`) → `@block_arc_temps` never sees it → no scope-end `rc_dec`.

## Central finding (D1 resolved — no byte-buffer producer has a drop site)

**Every dynamic-String byte-buffer producer (items #1–#20) has no scope-end drop site** —
inferred from lowering shape, then confirmed empirically by the D1 owned-return dump below. They lower
either to `HIR::ExternCall` (byte_slice, substring, gsub/_char/_regex, repeat, split,
`String * Int`) — verified at ast_to_hir.cr:59234, 72865, 72926, 72971–72988, 87314, 87679 —
or to `MIR::StringInterpolation` (interpolation and 2-part concat) — hir_to_mir.cr:7532,
emitted directly by `emit_string_interpolation` (llvm_backend.cr:25426–25700). Neither is an
`HIR::Call`, and `@block_arc_temps` is gated on `HIR::Call`. Container stores *do* `rc_inc`
(FieldSet 3120, IndexSet/array 3490, ctor-arg 2443), so a stored String is retained, but the
**producer temporary itself is never dropped**.

**D1 RESOLVED (empirical, 2026-06-18).** Built stage1 with an env-gated `@owned_return_funcs`
membership dump (`ADAMAS_OWNED_RETURN_DUMP`, instrumentation NOT committed) and compiled a
string-heavy prelude program (`/tmp/er0_d1_strings.cr`: concat + interpolation + byte_slice +
`String.build`). The set had 68 members. **Zero** byte-buffer producers are tracked — grep
counts of `Dnew`, `byte_slice`, `substring`, `gsub`, `string_concat`, `interpolat`, `repeat`,
`split`, `_to_string` in the set are all **0**. The ONLY String-typed-result members are the
high-level constructors `String.new$String`, `String::Builder.new`, `String::Builder.new$Int32`
— none of which is the low-level `String$Dnew$$Pointer$LUInt8$R…` allocator (item #1) or any
ExternCall/StringInterpolation producer. So the byte-buffer producer surface (items #1–#20)
has **no scope-end drop site**, now empirically confirmed, not just inferred.

Design constraint for the §11.7 whitelist (from D1): `String::Builder.new*` and
`String.new$String` are already tracked & dropped as `HIR::Call` owned-returns. They are
disjoint from the ExternCall/interpolation producers (different allocated objects — a Builder
object, resp. the `String.new(String)` result, vs. the raw byte-buffer), so the additive E
whitelist will not double-drop them — **verify this disjointness holds in P2** before enabling
the gate.

**Consequence — E is two independent bodies of work, and the drop-site one is the larger:**

1. **Layout unification** (SDD §4 `__adamas_alloc_string`): migrate Regime-B → headered so
   RC is even *possible*. Necessary; ~18 producers.
2. **Drop-site emission** (the bulk, generalizes GPT's interpolation-specific §2.7 catch to
   the whole ExternCall surface): extend the scope-end `rc_dec` mechanism to cover
   `ExternCall` and `MIR::StringInterpolation` results that are owned String temporaries —
   `@block_arc_temps`'s `HIR::Call`-only gate must be widened, OR a parallel String-aware
   drop pass added. Without this, layout migration frees nothing.
3. **Retain/release balancing** (SDD §7): once 1+2 land, balance container store/evict,
   borrowed returns, slice aliases, Builder transfer.

This resizes E again: layout migration is the *cheap* part; drop-site emission + balancing
is where the correctness risk and the work live.

## Producer table

Lines are `src/compiler/mir/llvm_backend.cr` unless noted. "verified" = alloc shape read
byte-for-byte this session or prior; "pattern" = confirmed `__adamas_malloc64` + header-store
at base (grep-confirmed header store line) but full alloc arithmetic not re-read this session.

| # | Producer | def | Layout | Evidence | Ownership / drop-path |
|---|---|---|---|---|---|
| 1 | `String$Dnew$$Pointer$LUInt8$R_Int32_Int32` | 10556 | **A** (`+21`, sentinel, raw+8) | verified | **none** — NOT in `@owned_return_funcs` (D1 confirmed: 0 `Dnew` entries) |
| 2 | `__adamas_runtime_string_from_cstr` | 7634 | **A** (`+21`, sentinel) | verified | bootstrap startup; result held by a const — borrow/global |
| 3 | `__adamas_string_byte_slice` | 7502 | **B** (`+13`) | verified (7519) | **none** — ExternCall (ast_to_hir 87314) |
| 4 | `__adamas_string_substring` | 7607 | **B** (→ create_substring) | verified (7627) | **none** — ExternCall (72865/87679) |
| 5 | `__adamas_create_substring` | 8143 | **B** (`+13`) | verified (8145) | **none** — called by #4 |
| 6 | `__adamas_string_concat` | 8931 | **B** (`+13`) | verified (8953) | **none** — via StringInterpolation 2-part path (25690); **null passthrough** `ret %a/%b` (8941/8946) = borrowed |
| 7 | `__adamas_string_interpolate` | 8977 | **B** (`+13`, 9018) | pattern | **none** — MIR::StringInterpolation (25699) |
| 8 | `__adamas_string_repeat` | 9100 | **B** (header 9127) | pattern | **none** — ExternCall `String * Int` (59234) |
| 9 | `__adamas_string_gsub` | 7347 | **B** (header 7399) | pattern | **none** — ExternCall (72979) |
| 10 | `__adamas_string_gsub_char` | 7457 | **B** (header 7470) | pattern | **none** — ExternCall (72972) |
| 11 | `__adamas_string_gsub_regex` | 9605 | **B** | pattern | **none** — ExternCall (72988) |
| 12 | `__adamas_string_split_string` segments | 8162 | **B** (headers 8247/8276/8328/8363) | pattern | **none** — ExternCall (72926); segments stored into Array → `rc_inc` on store, no temp drop |
| 13 | `__adamas_int_to_string` | 8399 | **B** (`+13`) | verified (8404) | **none** — `.conv` temp in `emit_string_interpolation` |
| 14 | `__adamas_int64_to_string` | 8420 | **B** | pattern | **none** — `.conv` temp |
| 15 | `__adamas_f64_to_string` | 8777 | **B** (header 8785) | pattern | **none** — `.conv` temp |
| 16 | `__adamas_bool_to_string` | 8811 | **B** (header 8835...) | pattern | **none** — `.conv` temp; may return a `.data` literal ("true"/"false") — **audit (D2)** |
| 17 | `__adamas_char_to_string` | 8821 | **B** (fixed 16) | verified (8834) | **none** — `.conv` temp |
| 18 | `__adamas_array_i32_to_string` | 8022 | **B** (headers 8563/8577/8590) | pattern | **none** — `.conv` temp |
| 19 | `__adamas_array_string_to_string` | 8081 | **B** (headers 8666/8682/8698) | pattern | **none** — `.conv` temp |
| 20 | `String::Builder#to_s` (stdlib) | builder.cr:100–115 | **B** (adopts `@buffer` in place) | verified | **none** — `@buffer` is `Pointer(UInt8)`, not auto-freed (has_ref_field gate 9256); see SDD §11.6 |
| — | static `.data` literals | 5884–5922 | literal (sentinel) | verified | n/a — never freed (SDD §5) |
| — | `@.str.empty` / `ret_empty` paths | various | literal | — | n/a — shared singleton |

## Open audits surfaced by the census (feed back into SDD §11)

- **D1 — `String.new` / `String$Dnew` call shape. — RESOLVED 2026-06-18 (empirical).** The
  low-level `String$Dnew$$Pointer…` allocator is NOT in `@owned_return_funcs` (0 `Dnew`
  entries in a 68-member dump over a string-heavy prelude compile). No byte-buffer producer
  is tracked. Only high-level `String.new$String` / `String::Builder.new*` are tracked, and
  they are disjoint from the producer surface (see Central finding). The drop-path gap over
  items #1–#20 is therefore confirmed total. Method: env-gated `ADAMAS_OWNED_RETURN_DUMP`
  print after the closure loop in `build_owned_return_set` (hir_to_mir.cr ~2596),
  instrumentation NOT committed.
- **D2 — literal-returning conversions.** `bool_to_string` and any helper that may `ret` a
  `.data` literal must be classified borrow/literal for those branches (no rc), fresh for the
  alloc branches. Audit each branch before flipping rc on the result.
- **D3 — split segments ownership.** Segments are fresh Regime-B allocs stored into an Array;
  the Array `rc_inc`s on store (3490) but the loop temporaries are never dropped. After E,
  the store-retain + array-evict-release pair must balance (E-R3), and the segment temp must
  not be double-counted.

## What this census does NOT yet settle

- The exact `@owned_return_funcs` membership for String methods (needs the D1 empirical dump).
- The precise alloc arithmetic of the "pattern"-marked producers (#7–#12, #14–#16, #18–#19);
  layout is confidently Regime B from the shared malloc+header-at-base shape, but byte-exact
  re-read is deferred to P2 migration (each is touched then anyway).
- The Builder decision (SDD §11.6 a1/a2/b) and the interpolation/ExternCall drop-path decision
  (SDD §11.7) — both remain owner/P1 decisions; this census supplies the evidence for them.

## Appendix — D1 owned-return dump evidence (2026-06-18)

Command: `ADAMAS_OWNED_RETURN_DUMP=1 ./bin/adamas_d1 /tmp/er0_d1_strings.cr` (prelude compile,
rc=0). `@owned_return_funcs` size = **68**.

Negative confirmation (grep counts within the 68-member set):

| token | count |
|---|---|
| `Dnew` | 0 |
| `byte_slice` | 0 |
| `substring` | 0 |
| `gsub` | 0 |
| `string_concat` | 0 |
| `interpolat` | 0 |
| `repeat` | 0 |
| `split` | 0 |
| `_to_string` | 0 |

String-typed-result members present (the only ones): `String.new$String`,
`String::Builder.new`, `String::Builder.new$Int32`. (Plus error/Array(String)/Time::Location
constructors that take a String arg but return a non-String object.)

Conclusion: the dynamic-String byte-buffer producer surface (items #1–#20) is entirely
outside `@owned_return_funcs`, so no scope-end `rc_dec` is emitted for any of them today.
