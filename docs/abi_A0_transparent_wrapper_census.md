# A0 — Transparent-Wrapper Struct ABI Census (read-only design packet)

Status: **DESIGN / CENSUS ONLY — no behavior.** Arc A, stage A0. CAUTION-tier.
Predecessor: SDD `docs/root_struct_union_call_abi_sdd.md` §1–§10 (slices 1–3 + tactical B
falsified). This packet scopes arc A; it does **not** implement the ABI rewrite and does **not**
choose the representation. Claim discipline: "A is mandatory for this frontier" is supported;
"A implementation path is known" is **not yet** supported.

## 1. Scope — exactly which wrappers (and which are out of scope)

The crashing family is **transparent single-field wrapper structs that cross self-hosted call /
return / union boundaries**. The actual wrapper *structs* in the compiler are:

| Wrapper | Definition | Payload | Note |
| --- | --- | --- | --- |
| `Adamas::HIR::TypeRef` | hir.cr:91 | `id : UInt32` | the crashing one; `null_ptr? = pointerof(@id).address == 0` (a self-guard that only makes sense under a *by-pointer* repr — direct evidence of the dual-repr) |
| `Adamas::MIR::TypeRef` | mir.cr:449 | `id : UInt32` | sibling; `from_hir` |
| `Adamas::Compiler::Frontend::ExprId` | ast.cr:24 | `index : Int32` | same shape; the 21791-21795 comment names ExprId as the motivating case |

**Out of scope (important correction to the initial candidate list):** `ValueId`, `BlockId`,
`FunctionId`, `TypeId` are `alias … = UInt32` (hir.cr:18–30, mir.cr:23–26) — they are **primitives,
not wrapper structs**, so they already cross every boundary as `i32` and carry **no** ABI hazard.
A0 therefore narrows the root to the **3 single-field wrapper structs above**, plus the
**`Nil | <wrapper>`** nilable/union forms adjacent to them (the shape behind 6a1662c4 and the MIR
frontier).

## 2. ABI matrix — what the repo currently emits per dimension

Source of truth for cross-frame LLVM typing: `compute_llvm_type_for_type` (llvm_backend.cr:294) and
`TypeMapper#llvm_type` (:189→:294). Locals use `llvm_alloca_type` (:207). The only scalar↔ptr
bridge for a wrapper is `transparent_wrapper_struct_scalar_llvm_type` (:26958), wired at **one**
call site (:21812).

| ABI dimension | Current emitted repr for a transparent wrapper | Site | Bridge present? |
| --- | --- | --- | --- |
| **Call param** | declared `ptr` (struct→ptr @309). Actual = scalar `iN` → materialized to a stack slot, pass `ptr %slot` (:21812). Actual = already `ptr` → **passthrough `ptr %val`, no check whether it is a storage addr vs a packed/null token** (:21797). | :21791–21840 | partial (scalar only) |
| **Return** | declared `ptr` (struct→ptr @309). Value returned as-is. | Return @15186/26269 | **none** |
| **Field storage** | `ptr` slot / `InlineBytes` memcopy; load always yields a ptr. | emit_store @17990; lower_field_store_to_ptr | **none** |
| **Local / load** | alloca'd as the **real** `%TypeRef` struct (:211); loaded/stored as the struct in-frame; escapes as `ptr`. | llvm_alloca_type:207 | n/a (in-frame ok) |
| **Union payload** (`Nil | TypeRef`) | union aggregate `%Name.union` (@318), payload slot typed via struct→ptr. | emit_union_wrap @23787 | **none** |
| **Phi / cross-block** | `ptr` (struct→ptr); ptr-phi with int_to_ptr fixups. | emit_phi @20412; @16125 | n/a (ptr-uniform) |
| **Container / `Pointer(T)` element** | `ptr` element (struct→ptr); element type erased to opaque `Pointer` (see SDD slice-3). | element llvm @18350/24528 | **none** |

### The 3-way collision (where the repo disagrees with itself)
- `compute_llvm_type_for_type` says **`ptr`** for the wrapper at *every* cross-frame position.
- `llvm_alloca_type` says the wrapper is a **real `%TypeRef` struct** for *locals*.
- the call-param bridge (:21812) says a wrapper actual is a **scalar `iN`** (→ materialize to slot).
- the **consumer** (callee body reading `type.id`) **dereferences** the `ptr` → it *requires* a
  real storage address.

So a wrapper value flows as one of three incompatible things — (a) real-struct storage addr, (b)
opaque/packed `ptr` token (passthrough param, return, union payload), (c) scalar `iN` — and the only
place (a)↔(c) is reconciled is **call-param when the actual is a scalar**. Everywhere else the reprs
flow **unbridged**. The MIR frontier crash is exactly case (b): a callee derefs a `ptr` that the
caller passed as a packed/null token (tactical B confirmed `.id` is undereferenceable at every
frame in the chain).

## 3. Representation candidates (compared, not chosen)

### Candidate 1 — Scalar cross-frame ABI for transparent wrappers
Wrapper crosses **every** frame boundary (param, return, union payload) as its scalar `iN`; `.id`
is read directly as the scalar; locals stay real `%TypeRef`.
- **Required changes:** `compute_llvm_type_for_type` (return wrapper scalar at param/return/union
  positions), `emit_call` (drop the :21812 materialization, pass `iN`), Return emit (return `iN`),
  callee prologue / every `.id` read (read the `iN` param directly — no deref), `emit_union_wrap`/
  unwrap (payload = `iN`), and `get_type_descriptor`/all `.id` consumers stay valid (already take
  the id).
- **UAF risk:** **none** — no pointer, no lifetime. (This is the decisive advantage; it also
  dissolves the borrow/escape hard-stop that blocked the earlier tactical slice.)
- **Affected paths:** all call/return/union sites carrying a wrapper. Field-storage is *not* forced
  to change (locals already real struct; fields only escape via call/return).
- **Isolable to call-param only?** **No** — a scalar-param ABI with a still-`ptr` return ABI would
  mismatch the moment a wrapper is returned. Minimal coherent unit = **{call-param + return +
  union-payload}** under one rule "transparent wrapper → scalar at every cross-frame boundary".

### Candidate 2 — Storage-address cross-frame ABI for transparent wrappers
Wrapper crosses every boundary as a **pointer to a valid `%TypeRef` storage**, with **guaranteed**
materialization (never a packed scalar / null token).
- **Required changes:** extend the :21812 materialization to **all** positions incl. the :21797
  passthrough (materialize unless the ptr is *proven* storage), Return emit (materialize), union
  wrap (materialize), **plus a borrow/escape analysis** so a materialized stack slot never escapes
  its frame.
- **UAF risk:** **high** — materialized stack slots passed/stored/returned by pointer can dangle;
  needs escape analysis (this is exactly GPT hard-stop #2 from the tactical phase).
- **Affected paths:** all producer sites; plus a new escape pass.
- **Isolable to call-param only?** No (same reason) and it is strictly *more* invasive than C1.

## 4. Reducers / falsifiers (identified; to be authored in A1, not now)

The bug is **s2b-only** (stage1 reads `field.type.id` fine), so a standalone stage1 program does
not crash — the only true carrier today is the **gated s2b build on `/tmp/med.cr`**. A0 identifies
the falsifier set to author *before* any A1 behavior:
1. **2-frame `.id`**: pass a `HIR::TypeRef` through two helper frames and read `.id` in the inner
   one (mirrors `lower_field_set → lower_field_store_to_ptr → hir_type_is_lib_struct?`).
2. **`Nil | TypeRef` boundary**: a nilable wrapper crossing a call adjacent to a `String`/ref arg
   (the 6a1662c4 / union-arg shape).
3. **Overloaded constructor**: the `Call.new(…, Nil|UInt32, String, …)` family from 6a1662c4.
4. **Field-set chain**: `/tmp/med.cr` (the live MIR-frontier carrier) + gated s2b as the oracle.
Each must be checked **both** under stage1 (must stay clean) and under the gated s2b build (the
crash oracle), since the divergence *is* the bug.

## 5. Hard-stop determination

Per the A0 hard stop: the lower-risk candidate (C1, scalar) **cannot be isolated to call-param
only** — it requires a coherent **{call-param + return + union-payload}** change. Therefore A0
**stops short of proposing an immediate gated A1** and instead hands back a **staged migration
plan** (no "one big patch"):

- **A1 (gated, first behavior slice):** C1 scalar ABI for the **call-param + return pair** of the
  3 wrappers, behind `ADAMAS_WRAPPER_SCALAR_ABI=1`, landed only after falsifiers #1–#3 are authored
  and pass under stage1 **and** advance the gated s2b oracle. Drop the :21812 materialization on the
  gate path.
- **A2 (gated):** extend C1 to the **union payload** (`Nil | TypeRef`) — only if A1 reducers show
  the param+return pair is sound in isolation and the union path is the next s2b frontier.
- **A3 (cleanup):** remove the dual-repr (the :21812 bridge, the `null_ptr?` self-guards) once
  param+return+union are uniformly scalar; re-baseline suites.

Each stage is one gated commit with its own reducers and a stage1-green + s2b-advance DoD; behavior
never lands without review (commit policy: A0 is doc-only).

## 6. Verdict (calibrated)

- **A is mandatory for this frontier** — SUPPORTED (tactical B falsified empirically; the dual-repr
  is structural, see §2 collision).
- **Recommended representation: Candidate 1 (scalar)** — it carries **no UAF risk** and matches the
  wrappers' actual semantics (they *are* scalar ids). Candidate 2 re-imports the escape hazard that
  already blocked the tactical slice. This is a recommendation with evidence (UAF surface), **not**
  a final decision — A1's reducers are the deciding falsifier.
- **"A implementation path is known"** — NOT yet supported: the param+return+union coupling means
  even C1 is a staged migration, and its first slice must be proven by reducers before it is trusted.
