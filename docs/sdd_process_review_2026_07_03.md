# SDD Process Review — 2026-07-03

> Status: accepted by owner 2026-07-03.
> Scope: hostile review of the SDD-driven codegen rewrite process, 2026-06-15 → 2026-07-03
> (382 commits), and the document surgery derived from it.
> Method: three independent audits — (1) line-level review of
> `compiler_architecture_sdd.md`, (2) review of `compiler_refactor_architecture_plan.md`
> + `specs/05-falsifier-matrix.md` with existence checks for all 50 referenced scripts,
> (3) full-commit taxonomy validated against diffs, B5 classification timeline, and
> diagnostics-load counts.

## 1. Verdict

Direction is correct; the engineering loop underneath is real; but starting exactly
2026-07-01 (`a3a4e6ca "docs: seal architecture acceleration checkpoint"`) the process
entered a self-sustaining bureaucratic mode that grows text and gates faster than it
produces compiler behavior.

Substance, to be fair against the "it's all bureaucracy" bias:

- **B4 went green 2026-07-03**: produced `cv2_s2` compiles full-prelude `puts 42` in
  both LLVM worker modes and the produced binary runs
  (`classification=clean_both_modes`). This is the largest bootstrap capability
  milestone in months.
- It was delivered by ~6 conventional "emergency-lane" fixes (function-emission
  outcomes → output-ownership restore → `String::HEADER_SIZE` classvar global →
  return-contract → zero-struct sentinels → GC-realloc declaration demand), i.e. by the
  June-22–30 working mode — **not** by the behavior-neutral owner-helper stream that
  consumes most July commits.
- B5 (s2 self-build, target `Adamas::Compiler::CLI#run$IO_IO`) was localized in a
  single day (07-03) through 8 successively finer stop boundaries down to
  `AstToHir#lower_method` body lowering (~4.8 GB, exit 139). Legitimate localization.
  Since 18:27 that day the classification string is frozen while 4 behavior-neutral
  owner-helper slices each re-ran the full ~20-minute verification pipeline to confirm
  it verbatim unchanged.

## 2. Measured facts

| Metric | Value |
|---|---|
| Commits Jul 1–3 | 182 (48% of 3-week volume); **3.3% change compiler behavior** |
| Jun 22–30 baseline | fix share 40%→60%; six s2b root causes burned down |
| Lines written in 3 weeks | docs 33,762 + scripts 16,783 + src 13,287 + tests 7,680; durable compiler logic ≈ **9.5% of total** |
| `compiler_architecture_sdd.md` | 1,045 lines (Jun 25) → 12,847 lines / 650 KB in 8 days; the actual spec starts at line 7460 (58% deep) |
| Diagnostics compiled into product | `ADAMAS_STOP_AFTER*` env gates: 3 → 76; `ast_to_hir.cr` +4.6k lines (~49% of all src additions are diagnostics) |
| Scripts | +57 in 4 days (guard/classifier/report/census); 90 total |
| Regression coverage in July | zero new tests (152/152 + 36/36 frozen since Jun 29) |
| Per-slice verification cost | stage1 build + cv2_s2 (231–253 s) + full suites ≈ 20 min machine time, paid identically by a 30-line neutral extraction and a real fix |

Additional ground truth: on Jun 30 the s2→s3 frontier was already localized inside HIR
lowering (`04322d4f` commit body: `NodeSlot#node ← AstArena#[] ← stringify_type_expr ←
lower_call`) — the July process re-derived approximately the known position.

## 3. Failure mechanisms

1. **Authority inversion in the SDD.** "Target architecture" (§6) was a good spec but
   remained the untouched Jun-25 original, while ~12 owner records actually got built
   (`LLVMEmissionSession`, `MaterializationTransaction`,
   `MethodBodyLoweringScopeSnapshot`, …) and were recorded only as ledger entries. The
   spec stopped describing the system; the 11.6k-line non-chronological ledger became
   the only truth — while itself stating that needing to read the historical ledger
   means the process gate has already failed.
2. **Unfalsifiable rituals.** The 13-field `SliceReceipt`; the "lexicographically
   decreasing" `BootstrapPotential` 4-tuple whose components were never once reported
   numerically in 12,847 lines; a ~10-item prohibition litany repeated ~187 times.
3. **Falsifiers guarding ceremony.** ~30% of the falsifier matrix are genuine behavior
   oracles (B3/B4/B5, H-family, L19–L22 — keep). ~40% are source-shape guards (awk
   asserting "the refactor was applied") plus process-law rows P6–P14 whose failure
   condition is *a commit without paperwork*. Those guard the protocol, not the
   compiler.
4. **Fixed cost per step at zero step size.** Every slice — including behavior-neutral
   ones that explicitly disclaim progress — pays the full ~20-minute bootstrap
   verification on a shared machine. The process diagnosed its own pathology at least
   four times in writing ("bookkeeping, not bootstrap progress", "report churn",
   "wrapper theater", "diagnostic debt") and each time responded with another gate.

## 4. What is genuinely good (keep)

- `docs/specs/00–03, 06` (May): concrete MUST/SHOULD invariants, named falsifiers,
  recorded refuted branches. Untouched by the drift.
- The original SDD spec core (sections 1–10, 12, slice boundaries A–D): ownership
  model, data contracts, design laws, migration phases.
- Behavior oracles B3 (original-vs-stage semantic diff), B4, B5 and the executable
  guard scripts — all 50 referenced scripts exist and the executable ones run real
  binaries.
- The R-section of refuted branches (blocks retrying dead approaches).
- The Jun-22–30 working mode itself: reducer → root cause → fix → narrow guard →
  suites. It measurably delivered, including B4 green.
- The best pure-architecture writing in the repo is the 0k-BQ source-inventory table
  and `LLVMEmissionSession` record definition — produced *by* this process, buried in
  the ledger.

## 5. Prescription (executed as the 2026-07-03/04 document surgery)

1. `compiler_architecture_sdd.md` → reduced to the durable spec: sections 1–10 and 12,
   slice boundaries A–D, §6 updated with every owner record actually built, one
   authority-edge state table (edge → owner → guard script → status), current frontier
   statement. The ledger is recoverable via
   `git show 95539f64:docs/compiler_architecture_sdd.md`.
2. `compiler_refactor_architecture_plan.md` → note stack evicted (recoverable via
   `git show 95539f64:docs/compiler_refactor_architecture_plan.md`); the original
   Phase-0–5 plan kept as a deferred reference (revisit after s3b).
3. `specs/04-llvm-emission.md` §7 → the 0k-BQ…0k-CC slice log collapsed to a
   current-state contract statement.
4. `specs/05-falsifier-matrix.md` → behavior oracles and refuted branches kept; stale
   frontier pins (superseded by B4 green) and process-law rows P6–P14 removed; cell
   changelogs stopped.

## 6. Process rules going forward (replace the ceremony)

1. **Working loop**: reducer → root cause → fix → narrow guard → suites. Progress
   metrics are exactly two: movement of the B5 classification string and regression
   coverage growth. `SliceReceipt` and `BootstrapPotential` are retired.
2. **Owner migrations are pull-based.** Extract an owner/helper only when a concrete
   behavior fix needs that boundary — never as a standalone work stream. A
   behavior-neutral extraction does not require a full bootstrap re-verification cycle;
   batch neutral slices and verify once.
3. **SDD document contract**: no dated entries in the SDD; the work log lives in
   `TODO.md` and git history. An owner record is not "consumed" until it is written
   into §6 of the SDD. New source-shape guard scripts are not minted; existing ones may
   be deleted when their migration is absorbed into §6.
4. **Probe hygiene**: `ADAMAS_STOP_AFTER*` / probe gates are removed when their
   frontier is passed (same rule as lldb probes). Current count: 76; target: shrink
   monotonically.
5. **Dodge ledger**: self-host workarounds that route around stage2 miscompiles (e.g.
   `members.keys.find { }` → manual `while` because stage2 miscompiles block-`find`)
   are real open bugs and are tracked as a list in `TODO.md`; each needs an eventual
   root-cause fix + reducer, or it will return.

## 7. Immediate technical next step

Not more owner migrations. Continue the B5 descent in emergency-lane mode:
`AstToHir#lower_method` body lowering of `CLI#run$IO_IO` in the self-build,
~4.8 GB, exit 139; first bad stop
`ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`. The uncommitted
`[B5_CALL_PRED]` probes in `ast_to_hir.cr` are mid-bisection of `lower_call`
predicates on that path.
