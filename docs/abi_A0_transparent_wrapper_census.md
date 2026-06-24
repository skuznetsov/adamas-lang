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

## 7. A1 risk matrix (bridge points) — gate BEFORE any reducer/behavior

Hostile review (GPT) flagged that the staged plan is VULNERABLE until the bridge points are
enumerated and each changed one has a reducer or a fail-closed gate. This section is the census of
those bridges for Candidate 1 (scalar). It is the gate: **no A1 behavior starts until every "bridge
required" cell below has a reducer or an explicit fail-closed gate.**

### Bridge-point table (C1 scalar ABI)
| Bridge point | Current repr | A1 (C1) | Bridge required | Reducer (to author) |
| --- | --- | --- | --- | --- |
| **Call param** | `ptr` (+:21812 scalar→slot) | scalar `iN` | callee prologue: `iN` param → in-frame `%TypeRef` (store to a local alloca) so existing `.id`/struct reads stay valid | R1 two-frame `.id` |
| **Return** | `ptr` | scalar `iN` | producer: in-frame `%TypeRef` → return `iN` (load `.id`) | R2 helper-returns-TypeRef |
| **Union payload** `Nil|wrapper` | `%Name.union` aggregate, payload via struct→ptr | payload scalar `iN` | wrap/unwrap must place/read `iN`; discriminator unchanged | R3 `Nil\|TypeRef` cross+unwrap |
| **Local alloca** | real `%TypeRef` (:211) | **unchanged** | **yes (both ways)** — param-scalar→local and local→return-scalar: this is the split-brain seam (risk 1) | R1+R2 transition checks |
| **Field load/store** | `ptr`/InlineBytes (:17990) | **unchanged** locally | **yes** — the live frontier's wrapper ENTERS via `FieldSet.type` field-load (hir.cr:175); field-load→call must bridge `%TypeRef`→`iN` | R4 field-set chain (`/tmp/med.cr`) |
| **Phi / cross-block** | `ptr`-uniform (+int_to_ptr) | scalar `iN` if a scalar wrapper crosses a block | maybe — only if a wrapper SSA spans blocks as scalar | R5 cross-block wrapper |
| **`null_ptr?` guards** | `pointerof(@id).address == 0` | meaningless under scalar | **yes** — 94 call sites (incl. `sizeof(TypeRef)<=8 &&` at ast_to_hir.cr:5587); must become an id-sentinel test or keep storage on guarded paths (risk 5) | R6 call `null_ptr?`/`invalid?` on a wrapper |

### What the census forces (revising §5)
1. **The frontier's minimal coherent unit is NOT {param+return}.** Live code: the crashing wrapper
   originates from a **field-load** (`FieldSet.type`) and the same signature carries a
   `Nil | MIR::TypeRef` **union** param. So the smallest unit that could make the frontier coherent
   is **{field-load → param} + the adjacent union**, not param+return. Deferring union (proposed A2)
   would leave the frontier's own signature half-converted → "A1 green, s2b still dies" (risk 4
   realized). **A1 must re-census, per concrete s2b IR, exactly which crossings feed THIS frontier
   before committing to a unit.**
2. **`null_ptr?` is not cleanup (risk 5).** 94 sites depend on `pointerof(@id)`; scalar ABI silently
   flips them to always-false. A1 cannot touch param/return without simultaneously deciding the
   `null_ptr?` contract (id-sentinel vs storage-on-guarded-paths). This is a behavior change that
   needs R6 before any bridge lands.
3. **Predicate is structural, not 3 names (risk 2).** `transparent_wrapper_struct_scalar_llvm_type`
   already keys on shape (single field, offset 0, int field) and matches **more** than the 3
   wrappers. A1 must EITHER (a) explicitly gate to a tactical 3-name allow-list and label it
   tactical, OR (b) use the structural predicate **plus a negative-list** for single-field-int
   structs where scalar ABI is unsafe (identity-bearing, pointer-aliased, or `null_ptr?`-guarded),
   with negative tests. No silent middle ground.
4. **Reducers must include an IR/signature oracle (risk 3).** Because the bug is s2b-only and
   stage1 is always clean, a runtime-only reducer can be a value-proxy. Each A1 reducer must assert
   the **emitted `.ll`** (param/return/union slot type changed as intended), not just program output.

### Revised A1 DoD (test/docs only; no ABI code)
- R1–R6 authored as **ABI-matrix falsifiers** (not generic smoke), each with an **IR oracle** + a
  runtime check; red/diagnostic on current HEAD (not vacuous).
- stage1 stays clean; the gated s2b oracle still reproduces the current frontier **before** behavior.
- A separate **frontier-feed census** (item 1 above) resolved from real s2b IR → names the minimal
  coherent unit; recorded back into this doc as "reducers result / chosen A1 unit".
- No source behavior change in the reducer commit. Behavior begins only after the reducer packet
  shows a viable, coherent gated unit (and the `null_ptr?` contract is decided).

### Hostile verdict (self-applied)
This plan is **VULNERABLE, not ROBUST**, until the reducer matrix proves a coherent staged unit.
The census has already refuted the easy version (param+return-only): the live frontier couples
field-load + param + union + the `null_ptr?` contract. So A1 is **reducers + frontier-feed census
first**, and the "first behavior slice" is likely **larger** than param+return — which is itself a
reason to keep C1 gated/tactical until the structural-predicate-vs-allow-list question is answered.

## 8. Bounded scope census (decision: tactical allow-list) — structural blanket is UNSAFE

Decision (GPT): A1 = **Option 1, tactical gated allow-list**, not the structural blanket. The
gate is `name ∈ {Adamas::HIR::TypeRef, Adamas::MIR::TypeRef, Adamas::Compiler::Frontend::ExprId}`
**AND** `structural(single-field, offset 0, int)` — **fail-closed** (legacy `ptr` ABI) if the
structural check fails for an allow-listed name. Claim wording is fixed: A1 = "tactical scalar ABI
for three compiler-internal wrapper structs under a gate", **not** "transparent-wrapper ABI fixed";
the durable structural scalar ABI stays future work.

One-shot read-only census (probe `ADAMAS_WRAPPER_SCOPE_CENSUS`, run during the s2b build, then
removed — not committed) enumerated **every** type the structural predicate matches:

```
13 distinct single-field-int structs matched:
  ALLOW-LIST (3):  Adamas::HIR::TypeRef (@id:i32), Adamas::MIR::TypeRef (@id:i32),
                   Adamas::Compiler::Frontend::ExprId (@index:i32)
  NON-ALLOWLISTED (10):
    Atomic(Bool) (@value:i1), Atomic(Int32) (@value:i32),
      Atomic(Channel::SelectState) (@value:i32)   <-- CAS needs pointerof(@value); scalarizing breaks atomics
    Crystal::System::Kqueue (@kq:i32)             <-- fd identity
    Crystal::EventLoop::Polling::Arena::Index (@data:i64)
    Crystal::MachO::Nlist64::Type (@value:i8), Time::MonthSpan (@value:i64)
    Adamas::Compiler::Semantic::TypeId (@index:i32),
      Adamas::Compiler::Semantic::SemanticTypeId (@id:i32),
      Adamas::MIR::DwarfLocalShadowStoreBinding (@slot_id:i32)  <-- sibling id-wrappers (future work, not A1)
```

**Conclusion:** the structural predicate over-fires on **10** non-wrapper structs. `Atomic(T)` is
the decisive falsifier of Option 2 — its single `i32`/`i1`/`i64` field is the target of atomic
CAS, which operates on `pointerof(@value)`; a blanket "single-field-int ⇒ scalar ABI" would
silently corrupt every atomic. This is the empirical proof that the allow-list (Option 1) is
correct for A1, and it does **not** refute the allow-list (all 3 allow-listed names are present in
the structural set, so the AND-gate fires for them).

**Negative-test selection (risk 2, mandatory):** use `Atomic(Int32)` as the primary negative
(real, address-semantic) **plus** a hermetic synthetic single-field-int struct outside the
allow-list. The IR oracle for the negative reducer must assert the non-allow-listed type still
emits the **legacy `ptr`** ABI at param/return/union — i.e. A1 does **not** scalarize arbitrary
single-field-int structs. The sibling id-wrappers (`Semantic::TypeId`, `SemanticTypeId`,
`DwarfLocalShadowStoreBinding`) are noted as the same *family* but are **out of A1 scope** (only the
3 that demonstrably feed the s2b frontier) — they become future work once A1's durable form lands.

## 9. Frontier-feed census from real s2b IR (no reducers) — names the unit + one retraction

Derived from the actual s2b LLVM IR (`bin/adamas src/adamas.cr --emit llvm-ir`, gated), not source
shape. The HIR::TypeRef value flow through the crashing chain:

| Step | IR fact | boundary kind | repr |
| --- | --- | --- | --- |
| `Value#initialize` (super of FieldSet) | `store ptr %type, [self+8]` | field-**store** | `ptr` |
| `FieldSet.new`/`$Dnew` | `%r13 = [malloc(12)+8]` default written first; `super`/initialize overwrites @type with `ptr %type` | field-store (default+override) | `ptr` |
| `lower_field_set` | `%r30 = load ptr, [field+8]` → arg6 of `lower_field_store_to_ptr` | field-**load** + **param** | `ptr` |
| `lower_field_store_to_ptr` | `call …hir_type_is_lib_struct?(ptr %self, ptr %field_hir_type)` — **pure passthrough** (also to `==`, `convert_type`, `static_array?`, `inline_memcopy?`) | **param** | `ptr` |
| `hir_type_is_lib_struct?` | `%r2 = getelementptr [%type+0]; %r3 = load i32, [%r2]` — **derefs** | consumer read (`.id`) | deref `ptr`→`i32` |
| `TypeRef#==` (same passthrough) | guarded by `null_ptr?` (hir.cr:132) → returns early, **survives** | consumer read | guarded |

### Retraction (intellectual honesty)
An intermediate reading — "`FieldSet.initialize` elides the `@id`/`@type` stores" — was **WRONG and is
retracted.** `FieldSet < Value`; `initialize(id, type, @object, …)` passes `id`/`type` to
`super` → `Value#initialize`, which stores them **correctly** (`store i32 %id, [self+4]`;
`store ptr %type, [self+8]`). The 4 stores visible in `FieldSet.initialize` are its own 4 fields.
There is **no store elision.** (Verify-before-claim caught this before it shipped.)

### What the IR actually shows (robust)
- HIR::TypeRef crosses **uniformly and consistently as `ptr`**: field-store, field-load, and param
  are all `ptr`; stores/loads match — no misalignment, no elision.
- The runtime fault is a **null `ptr`** value reaching a consumer that **derefs without a guard**.
  `TypeRef#==` survives the same null via its `null_ptr?` guard; `hir_type_is_lib_struct?` lacks the
  guard and derefs `[null+0]` → SIGSEGV. So `null_ptr?` is **load-bearing IN-UNIT**, not a mere
  global hazard (this **revises §7**, which had it as only-global).
- The adjacent `Nil | MIR::TypeRef` union (`obj_mir_type`) is passed correctly **by-value**
  (`%…union`) and is **not** on the `field_hir_type` crash path.
- **No wrapper return** anywhere in the chain (`i32`/`i32`/`i1`).

### minimal_unit / excluded (answer to the census)
- **minimal_unit = { field-storage(`ptr`), param(`ptr`), `null_ptr?`-guard contract }** for
  HIR::TypeRef. Field-storage is **type-driven and broad** (every HIR object with a TypeRef field,
  via `Value#initialize`), so it is **not** a localized slice.
- **excluded_bridge_points = { return** (no wrapper return feeds this frontier)**, union**
  (passed correctly by-value, not on the crash path)**, phi** (not observed in the chain) **}.**
- **`null_ptr?` is IN-UNIT** ⇒ per hard-stop, no behavior until its contract is decided.

### The prior question that blocks reducers (must resolve first)
The fault is a **null `ptr`** reaching an **unguarded deref**. Two readings remain open and the IR
alone does not separate them:
1. **Legit sentinel** — the null `ptr` *is* the NIL/VOID TypeRef representation; the real defect is
   that `hir_type_is_lib_struct?` (and the `lower_field_store_to_ptr` chain) **omit the `null_ptr?`
   guard** that `==` has. Fix = add the guard (one/few functions), tactical, no ABI change.
2. **Corruption** — `field.type` *should* be a real type here and was nulled upstream; a guard would
   **mask** a real miscompile. Fix = the upstream value, or the scalar ABI.

These imply opposite fixes. **Writing R1–R6 scalar-ABI reducers now would be architecture theater**
until this is resolved. Next read-only step: trace whether the crashing `field.type` is expected to
be a concrete type (corruption) or legitimately empty (sentinel) for med.cr's field-set — by the
HIR `field_set` node's declared type at construction vs. its runtime null — before choosing any fix.

### Verdict (calibrated)
Per hard-stop #1, the unit is **field + param + null_ptr? together** (broad, type-driven), not a
small param/return slice — **too large for a casual A1**, exactly as the hostile review warned.
Per hard-stop #2, `null_ptr?` is in-unit → contract first. Per hard-stop #3, all of the above is
**derived from IR**, with the one elision misread explicitly retracted. **Recommendation: do NOT
write reducers yet**; resolve sentinel-vs-corruption first, because it selects between a tactical
guard fix (cheapest unblock) and the broad scalar-ABI arc.
