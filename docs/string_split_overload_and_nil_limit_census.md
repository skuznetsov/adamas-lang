# String#split — census + SDD brief (nilable-limit slice)

Status: **READ-ONLY CENSUS DONE. 2026-06-21.** No compiler edits. This is the
design/reducer-first slice GPT requested before any nilable-limit fix.

> **UPDATE 2026-06-21 — Bug 2 FIXED (gated, `ADAMAS_BLOCK_SHAPE_SPECIALIZE`, default OFF).**
> Per-shape block specialization emits distinct `Char_Int32_Bool_block`(i32) / `Char_Nil_Bool_block`(ptr)
> instead of one `$Char$arity3_block`; reducer `string_split_int32_nil_limit_collision_repro.sh`
> green (`int_limit=2 nil_limit=4`), no `inttoptr 2->ptr` / `load i32,ptr %limit`. The collapse
> root was a 4th, emit-time block-target site (`ast_to_hir.cr` ~78530). NOT default-on / NOT
> s2b-clean: gate-ON s2b clears this Globber/split startup crash but hits a separate backend
> `@value_def_block` crash in `LLVMIRGenerator#emit_function` (next frontier). **Bug 1 below is
> still open.**

The census
**refutes the single-root framing** in `docs/abi_cnarrow_s2b_smoke_readiness.md` and
memory `s2b_startup_crash_split_glob_localization`: the standalone wrong-count and the
s2b SIGSEGV are **two distinct bugs**, not one nilable-limit lowering root.

## TL;DR

| | Bug 1 — overload misdispatch | Bug 2 — nilable-limit monomorphization collision |
|---|---|---|
| Symptom | wrong count (`split('/')` → 1) | SIGSEGV |
| Standalone repro | `string_split_default_nil_limit_repro` | `string_split_int32_nil_limit_collision_repro` (new) |
| Is it the s2b crash? | **No** | **Yes** |
| Root layer | overload resolution (HIR) | block-specialization arg repr (HIR/MIR/backend) |
| Trigger | a single `String#split(Char)` arg | coexistence of an Int32-limit AND a nil-limit Char split |

GPT's handoff plan was framed around Bug 2 (nilable-limit). Bug 1 is a **new** finding
the plan did not anticipate; it is the visible standalone wrong-count and is independent
of Bug 2.

## Evidence (all on `bin/adamas`, HEAD 84ff31e4, no s2b/lldb needed)

Disambiguator probe (`/tmp/split_disambig.cr`):
```
"a a a".split('b') = 3    # whitespace split was performed ('b' bound to limit, ignored)
"a/b/c/d".split('/') = 1  # wrong (should be 4)
"a/b/c/d".split('/', 2) = 2   # correct (2nd positional arg forces the Char overload)
"x y z".split = 3         # genuine whitespace split, correct
```
`"a a a".split('b') = 3` is the killer: a whitespace split ran, so `split('/')` is being
routed to the no-separator `split(limit : Int32? = nil)` overload, **not** to a
"nilable-limit returns 1" path. That refutes the nilable-limit framing for the standalone
wrong-count.

### Bug 1 — overload misdispatch (Char arg bound to `limit : Int32?`)

IR for `"a/b/c/d".split('/')`:
```
call ptr @String$Hsplit$$Char(ptr @.str.49, i32 47)     ; '/' codepoint 47 passed as limit
define ptr @String$Hsplit$$Char(ptr %self, i32 %limit)  ; this is split(limit : Int32?)
  ...store i32 %limit into a Nil|Int32 union, call @String$Hsplit$$Nil$_$OR$_Int32_block
```
So the Char `'/'` is bound to the `limit : Int32?` parameter of the **whitespace** overload
`def split(limit : Int32? = nil)` (stdlib string.cr:3954), then "a/b/c/d" is whitespace-split
→ `["a/b/c/d"]` → size 1.

Root cause (`src/compiler/hir/ast_to_hir.cr`):
- `resolve_untyped_overload` (≈36571) selects by arity, not arg type. For `split('/')`
  (1 arg, no named args) it computes `prefer_non_named = true` because a compatible
  *non-named* overload exists — `split(limit : Int32?)` — and that check
  (`compatible_non_named_overload_exists_for_call?`, ≈36388) skips the arg-type check when
  `unknown_args` is set (line 36415), so it accepts the whitespace overload on arity alone.
- Then line ≈36577 `next if prefer_non_named && stats.has_named_only` **skips** the
  type-exact `split(separator : Char, limit = nil, *, remove_empty = false)` overload,
  purely because it has named-only params (`remove_empty` after `*`).
- Net: a type-exact Char→`separator` match is discarded in favor of a lossy Char→Int32
  numeric coercion into `limit`. (`integer_bit_width` treats `CHAR` as 32-bit, so
  `numeric_compatible?(Char, Int32)` is true — line ≈38535/38477.)
- When a 2nd positional arg or `remove_empty:` is present, the Char overload is selected
  correctly (`split('/', 2)`=2, `split('/', remove_empty: true)` works). So the defect is
  specific to the **single Char arg, no named args** call shape.

### Bug 2 — nilable-limit monomorphization collision (the s2b SIGSEGV)

IR for `split('/', 2)` + `split('/', remove_empty: true)` coexisting (`/tmp/split_bug2.ll`):
```
define ptr @String$Hsplit$$Char$$arity3_block(ptr %self, i32 %separator, i32 %limit, i1, ptr)
                                                                        ^^^ single i32 limit
define ptr @String$Hsplit$$Char_Nil_Bool(ptr %self, i32 %separator, ptr %limit, i1 %remove_empty)
  %load_from_ptr.0 = load i32, ptr %limit        ; ptr %limit is NULL for nil limit -> SIGSEGV
  call @String$Hsplit$$Char$$arity3_block(..., i32 %load_from_ptr.0, ...)
; call sites:
call @String$Hsplit$$Char_Int32_Bool(@.str.49, i32 47, i32 2, i1 0)       ; Int32 limit site
call @String$Hsplit$$Char_Nil_Bool (@.str.49, i32 47, ptr null, i1 1)     ; nil limit site
```
The block-specialized inner function `arity3_block` is monomorphized to a single
`i32 %limit` signature (driven by the Int32 site). The nil-limit wrapper `Char_Nil_Bool`
holds `limit` as a nilable `ptr` (null) and bridges to the i32 signature with an
**unguarded** `load i32, ptr %limit` (string_split_bug2.ll:194055) on the null pointer
→ SIGSEGV.

Why it is the s2b crash: `Dir::Globber` (`src/stdlib/dir/glob.cr:189`) calls
`glob.split('/', remove_empty: true)` — the nil-limit, named-arg form, i.e. exactly
`Char_Nil_Bool`. The compiler's own code also contains Int32-limit Char splits, poisoning
`arity3_block` to `i32 %limit`. So during require-glob resolution the Globber path hits the
null `load i32` and crashes — matching the lldb localization in the readiness doc
(`ldr w2,[x9]`, x9=0). The existing `string_split_default_nil_limit_repro` does **not**
reproduce this crash (it has no Int32-limit Char site to poison `arity3_block`); it only
catches Bug 1.

## Minimal fix targets (for the fresh fix slice — NOT done here)

GPT review (2026-06-21) accepted both claims as ROBUST and refined the directions below.

**Bug 2 (priority — unblocks the s2b crash). Direction (a), GPT-preferred.** Do **not**
collapse Int32-limit and nil-limit into one `i32 %limit` `arity3_block`: include the
**effective block-param repr/shape in the block-specialization monomorphization key** so an
Int32-limit inner and a Nil/nilable-limit inner do not share one `i32 %limit` signature.
GPT constraint: the key must be a **general block-specialization arg-shape key**, NOT an
ad-hoc "nilability bit for split". Forbid the unguarded `load i32, ptr %limit` bridge: a
nilable `ptr` limit must never be loaded as `i32` without a null test. (Alternative (b) —
carry `limit` as the `Nil|Int32` union through the block boundary uniformly and lower
`if limit && limit <= 1` against the union — is semantically cleaner but wider; (a) is the
narrower first move.)

**Bug 1 (correctness — independent). GPT constraint: do NOT touch
`numeric_compatible?(Char, Int32)` globally as the first move.** First investigate **why the
call reaches the untyped resolver at all despite a `Char` literal arg** — if it can be
routed through the typed scorer (`params_match_score`/`declared_type_match_score`, where
Char→separator:Char scores 2 vs Char→Int32? scores 1), fix there. Narrow fallback: when arg
types are known, do not let `prefer_non_named` skip a named-only overload that is a strictly
better typed match than the available non-named overload. Treat the global
`numeric_compatible?` Char/Int change as a last resort (CAUTION — affects all Char/Int
overload ranking).

## Reducers (red now; green = DoD for the fix slice)

- `regression_tests/string_split_default_nil_limit_repro.{cr,sh}` — **Bug 1** reducer
  (overload misdispatch / wrong-count): `default=4` expected; currently `default=1`.
- `regression_tests/string_split_int32_nil_limit_collision_repro.{cr,sh}` — **Bug 2** reducer
  and the **standalone s2b-crash reducer**: `int_limit=2 nil_limit=4` expected; currently
  SIGSEGVs.
- Post-fix must also keep: `split('/', 2)`=2, `split('/', remove_empty: true)`=N,
  whitespace `"x y z".split`=3 and `"x y z w".split(2)`=2, then an s2b `x=1` smoke,
  then the three C-narrow gates smoke.

## DoD for the Bug 2 fix slice (GPT-agreed)

```
bash regression_tests/string_split_int32_nil_limit_collision_repro.sh ./bin/adamas
# GREEN: RESULT int_limit=2 nil_limit=4

# IR-oracle: the null-load bridge must be gone. Expect ZERO matches:
#   String$Hsplit$$Char_Nil_Bool ... load i32, ptr %limit
# (emit with: bin/adamas --emit llvm-ir <bug2 repro> -o /dev/null)

bash regression_tests/string_split_default_nil_limit_repro.sh ./bin/adamas
# MAY remain red until Bug 1 (do NOT bundle the Bug 1 fix into the Bug 2 slice)

# then s2b x=1 smoke must no longer 139 at the split/Globber site
```

## Recommended order (GPT-agreed)

1. Fix Bug 2 first (it is the s2b crash; one fresh slice, direction (a) — general
   block-specialization arg-shape key).
2. Re-verify s2b `x=1` smoke goes green (was 139).
3. Fix Bug 1 (separate slice/commit) — single Char-arg split correctness; investigate the
   untyped-resolver routing first, avoid the global `numeric_compatible?` change.
4. Re-run the C-narrow gates smoke.

Bugs 1 and 2 are independent; keep them in separate commits (do not bundle with the
already-shipped C-narrow arc).

## CORRECTION 2026-06-24 — Bug 1 localization MOVED; fix attempt regressed (reverted)

Bug 1 is now proven to **feed the s2b self-host crash** (not just a standalone wrong-count): a
single Char-arg split inside the compiler's own `lower_allocator_initializer_body`
(`ast_to_hir.cr:29461` `init_defining_class = init_base_name.split('#').first`) returns the unsplit
full method name `Box#initialize`, so `lower_method` sets `@current_class = "Box#initialize"`, the
ivar lookup misses, and `@items = [] of UInt32` gets a null FieldSet type → MIR
`hir_type_is_lib_struct?` deref crash. Full chain + reducer:
`regression_tests/string_split_char_delimiter_repro.sh`, `docs/abi_A0_transparent_wrapper_census.md`
§12.

**The §48 localization (`resolve_untyped_overload` / `prefer_non_named` / `has_named_only`) is
STALE.** Probe (always-on, full compile): `resolve_untyped_overload` is **never called for split**.
`split('/')` resolves through the **M3/M4 typed resolver** `lookup_function_def_for_call` →
`resolve_call_input` → `resolve_call_resolution` → **`resolve_call_tuple`** (ast_to_hir.cr ~80308).
`ADAMAS_RESOLUTION_ASSERT=1` confirms it selects `String#split$Nil | Int32` (the whitespace
`split(limit : Int32?)` overload, Char→limit) for `split('/')`.

The SAME `next if prefer_non_named && stats.has_named_only` skip exists in `resolve_call_tuple`'s
candidate loop (~80746), and there `arg_types` is already local. But un-skipping the Char overload
is **not sufficient**: the typed scoring (~80799–80853) then flips on
`score += 2 if param_count == arg_count` (~80839), which rewards the whitespace overload (1 param ==
1 arg) over the Char overload (2 params: separator+limit), **outweighing** the type-exactness
(`params_match_score`: Char→separator:Char = 2 vs Char→limit:Int32? = 1).

**Fix attempt (REVERTED, hard-stop #5):** (a) don't skip a named-only overload whose positional
params EXACTLY type-match (`declared_type_match_score == 2`); (b) `score += 3` for a full positional
exact match. Result: target FIXED (`split('/')`=4, `"Box#initialize".split('#')[0]`=Box, frontier
chain resolved), but it **REGRESSED** two split shapes — `split('/', 2)` → 4 (limit dropped) and
`split("#")` (String overload) → 1. The flat exact-match bonus disturbs broad selection
(GPT hard-stop #5). Reverted; tree clean.

**Open: a surgical scoring fix in `resolve_call_tuple`** that makes a strictly type-exact positional
match dominate the `param_count == arg_count` arity bonus **without** disturbing the 2-arg Char
(`split('/', 2)`) or String-separator (`split("#")`) shapes — likely a comparison-level priority
(exact-match as a higher sort key than the arity bonus, applied only when the alternative is a lossy
numeric coercion) rather than a flat additive bonus. The four hard-stop negatives
(`split('/', 2)`, `split('/', remove_empty: true)`, `split(2)`, non-split numeric overloads) must be
part of the next attempt's DoD before any commit.

## LEDGER + REGRESSION DECOMPOSITION 2026-06-24 — selection fix is correct; it EXPOSES Bug 2 family

Read-only per-candidate ledger in `resolve_call_tuple` (removed) + a recreated temp patch (un-skip
named-only on exact positional match @ ~80790 + `score += 3` exact-match bonus), all isolated per
caller. Key facts:

**`split('/')` (1 Char arg) scoring (baseline):** the Char overload `String#split$Char$arity3` scores
`pms=2 exact=1` + `req==arg_count` bonus `+1` = **3** but is **SKIPPED** (`prefer_non_named` &&
`has_named_only`). The whitespace `String#split$Nil|Int32` scores `pms=1 lossy=1` + `param_count==
arg_count` bonus `+2` = **3** and is the lone non-block CANDIDATE → selected; even when un-skipped
the Char overload only **ties** (3 == 3) and the `param_count < best_param_count` tiebreak picks
whitespace (pc 1 < 2). So the flip is: `param_count==arg_count (+2)` for the 1-param whitespace
overload outweighs `exact type (pms 2 vs 1)` + `required==arg_count (+1)` for the 2-param Char
overload.

**The selection fix WORKS in isolation.** With (un-skip exact-match named-only) + (exact-match
beats arity), each call selects correctly on its own:
`split('/')`→`$Char$arity3` (=4), `split('/', 2)`→`$Char$arity3` (=2), `split("#")`→`$String$arity3`
(=2). So this is **not** a selection regression.

**The two "regressions" are MATERIALIZATION/monomorphization collisions the fix EXPOSES** (because
it now routes `split(Char)` to the Char overload instead of whitespace):
- `split('/', 2)` → 4 (limit dropped) when a nil-limit `split(Char)` coexists = **Bug 2** proper.
  `ADAMAS_BLOCK_SHAPE_SPECIALIZE=1` (the gated Bug 2 fix) **corrects it → 2**.
- `split("#")` (String) → 1 when ANY `split(Char)` coexists (proven by combo bisect:
  str_alone=2, str+split('/')=1, str+split('/',2)=1, str+whitespace=2) = a **Bug 2 SIBLING**
  (Char-separator and String-separator `$arity3` specializations collide). The gate does **NOT**
  fix this one.

**Conclusion / order (confirms the census's "Bug 2 first"):** the Bug 1 selection fix is sound but
**premature** — landing it first re-routes `split(Char)` into the Char overload and exposes both the
gated Bug 2 collision (Char nil/int limit) and an un-gated sibling (Char-sep vs String-sep). The
materialization layer (general block-specialization / `$arity3` monomorphization arg-shape key, the
Bug 2 direction (a)) must be fixed so coexisting Char/String/limit splits get distinct
materializations, **then** the Bug 1 selection fix lands cleanly with all negatives green. DoD for
the eventual Bug 1 commit must run the negatives in a **single coexisting program** (not isolated),
since isolation hides the collisions.

## STR-SIBLING MATERIALIZATION LEDGER 2026-06-24 (read-only) — missing key dimension in the gate

The Char-sep vs String-sep collision reproduces on **baseline** (no Bug 1 patch) via
`split('/', 2)` (already routes to the Char overload) + `split("#")`. Minimal:
`a = "a/b/c/d".split('/', 2); puts "x#y".split("#").size` → **`str=1`** with
`ADAMAS_BLOCK_SHAPE_SPECIALIZE=1` (gate ON); `split("#")` alone = 2.

**Materialization chain (LLVM IR, `--emit llvm-ir`):**

| | `split("#")` ALONE | `split("#")` + `split('/', 2)` |
| --- | --- | --- |
| String wrapper define | `String$Hsplit$$String_Nil_Bool(ptr %self, **ptr %separator**, …)` | `…(ptr %self, **i32 %separator**, …)` |
| call site | `…(ptr @.str, **ptr @.str.50**, ptr null, i1 0)` | `…(ptr @.str, **i32 %load_from_ptr**, ptr null, i1 0)` |
| inner yield target | `→ String$Hsplit$$String_Nil_Bool_block` (ptr sep) | `→ **String$Hsplit$$Char_Nil_Bool_block**` (i32 sep) |

So when a Char-separator split coexists, the **String-separator wrapper's `separator` param repr
collapses `ptr`→`i32`** and its inner yield bridges to the **Char** block (`Char_Nil_Bool_block`,
`i32 %separator`). The String `"#"` is then passed/loaded as an `i32` (a Char codepoint) → wrong
split → size 1.

**Exact collapse boundary:** `shape_keyed_block_target` (ast_to_hir.cr:5038), key =
`shape_keyed = mangle_function_name(base_method_name, block_arg_types, true)` (line 5049).
`block_arg_types` are the **block's yield types** (the split pieces — `String` for BOTH Char-sep and
String-sep splits). The method's **separator parameter type (Char vs String) is NOT in the key**, so
Char-sep and String-sep map to the **same** `@block_shape_specializations[shape_keyed]` entry (line
5058) and share one inner-block materialization — the first-registered (Char) wins, and the String
wrapper inherits its `i32 %separator`.

**Gate ON/OFF:** gate ON fixes Bug 2 proper (the inner block's **limit** repr Int32-vs-Nil, which the
key distinguishes) — `split('/', 2)` → 2. It does **not** fix the separator collapse (`str` stays 1),
because the key omits the separator type. This is **NOT a different materialization layer** — it is a
**missing key dimension in the gate's own `shape_keyed_block_target`** (answers adversary "key lacks
separator type / base method identity").

**Proposed generic fix target (NOT implemented):** extend the `shape_keyed_block_target` shape key
(line 5049) to incorporate the **method's positional parameter types** (the separator), not just the
block yield types — e.g. key on `mangle(base_method_name, method_positional_arg_types +
block_arg_types, true)`. Generic (no `String#split` special-case); it is the same gate function, so it
also subsumes Bug 2 proper. Next step (one generic materialization fix) must verify: (a) the String
wrapper's `separator` becomes `ptr` again and bridges to `String_Nil_Bool_block`; (b) Bug 2 proper
(`split('/', 2)`) stays green; (c) no over-specialization blowup; (d) all four negatives + the two
split reducers green in ONE coexisting program; (e) full 148/148 + 36/36. Only then the Bug 1
selection patch lands.
