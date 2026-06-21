# String#split — census + SDD brief (nilable-limit slice)

Status: **READ-ONLY CENSUS DONE. 2026-06-21.** No compiler edits. This is the
design/reducer-first slice GPT requested before any nilable-limit fix. The census
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
