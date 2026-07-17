# Inherited virtual-demand runtime matrix

Recorded: 2026-07-17 UTC from the isolated worktree at base
`baaac5782cada620dfd8208aa2dfe98f3eb8c0cc`.

The oracle command was:

```text
INHERITED_RUNTIME_LLVM_DIR=/private/tmp/inherited_runtime_llvm_final \
INHERITED_RUNTIME_LEDGER=/private/tmp/inherited_runtime_matrix_llvm_final.tsv \
regression_tests/inherited_virtual_demand_runtime_oracle.sh \
  /tmp/adamas_inherited_fix_final \
  /Users/sergey/Projects/Crystal/crystal/bin/crystal
```

Both compiler invocations and every produced binary were run through
`scripts/run_safe.sh`. Adamas used `--no-prelude`; original Crystal used
`build --prelude=empty -O0 --single-module`. The Adamas compiler digest is
`sha256:dfd2dc45204c4a093a244a965e1921e786f5e4955c4de61b7a7e9e88465e0272`;
the original compiler digest is
`sha256:2d3047d39ce46273b9027d4a4847b4344aac30942a2c36b69a9e8b680d9e5d76`.
The source generator is
`regression_tests/inherited_virtual_demand_runtime_oracle.sh` with digest
`sha256:d7cc5060bf0900ae41e2ff503944c8f6c651a0f9a8e8ccda2823a597aa3736d0`.

## Authoritative runtime result

| Mode | Descendants | Adamas compile/exit | Original compile/exit | Source digest |
|---|---:|---:|---:|---|
| `no_override` | 0 | 0 / 41 | 0 / 41 | `e5ad86b011f8e08b81e76b0d6874b7acd185cf1ef6ae34a6add12654131ad9d1` |
| `no_override` | 1 | 0 / 41 | 0 / 41 | `3627fc8794b3f6985b673d7e7f13feb67226eebba27206e528a8d962a3465293` |
| `no_override` | 8 | 0 / 41 | 0 / 41 | `c79d1177eb59239496007071e6dfd19b32488c7309e68465ea67ca233ebb4207` |
| `no_override` | 16 | 0 / 41 | 0 / 41 | `1b6b317507317963d7b61b36fe75f3965ded64b28b7cc681c8dc2f57e9634599` |
| `override` | 8 | 0 / 42 | 0 / 42 | `03993e6bce2aa4c05a812c957e1bac8c9690e8d39bf5579513ee54407539aff8` |
| `generic` | 8 | 0 / 41 | 0 / 41 | `4f1da7a0746f36918979386591c3583b68b48c2d3a6891fb20d0a105da018a6d` |
| `overload` | 8 | 0 / 0 | 0 / 0 | `f87a39afe4048af2933d8e2f3fc107d792a7df19ab6986733205041f5806ee06` |

The per-binary and per-LLVM digests are retained in the generated ledger at
`/private/tmp/inherited_runtime_matrix_llvm_final.tsv`; that path is
ephemeral. The durable claim is the exact source digest plus matching
compiler/runtime status above, not the binary bytes themselves.

## Fresh LLVM pair and forward census

Each row above also emitted one original and one Adamas LLVM file from the
same generated source. The durable machine-readable record is
[`inherited_virtual_demand_llvm_matrix_20260717.json`](inherited_virtual_demand_llvm_matrix_20260717.json);
the files and classifier reports were emitted under
`/private/tmp/inherited_runtime_llvm_final` and
`/private/tmp/inherited_runtime_llvm_census_final` for this run; these paths
are ephemeral and may be removed.

| Row | Original define/declare | Adamas define/declare | Forward matches | Original-only / Adamas-only | ABI / linkage mismatches | Semantic LLVM shape |
|---|---:|---:|---:|---:|---:|---|
| `no_override` d=0 | 4 / 4 | 128 / 160 | 7 | 1 / 281 | 0 / 3 | Parent `value(Int32)` 1; Child 0; vdispatch 0; direct Parent call |
| `no_override` d=1 | 4 / 4 | 128 / 160 | 7 | 1 / 281 | 0 / 3 | Parent `value(Int32)` 1; Child 0; vdispatch 0; direct Parent call |
| `no_override` d=8 | 4 / 4 | 128 / 160 | 7 | 1 / 281 | 0 / 3 | Parent `value(Int32)` 1; Child 0; vdispatch 0; direct Parent call |
| `no_override` d=16 | 4 / 4 | 128 / 160 | 7 | 1 / 281 | 0 / 3 | Parent `value(Int32)` 1; Child 0; vdispatch 0; direct Parent call |
| `override` d=8 | 5 / 4 | 130 / 160 | 7 | 2 / 283 | 0 / 3 | Parent 1 + Child 1 + vdispatch 1; dispatch call retained |
| `generic` d=8 | 5 / 4 | 129 / 160 | 7 | 2 / 282 | 1 / 3 | Parent `value(Int32)` 1; Box value 0; vdispatch 0; direct Parent call |
| `overload` d=8 | 5 / 4 | 130 / 160 | 7 | 2 / 283 | 0 / 3 | Parent Int32 1 + UInt64 1; Child 0; vdispatch 0; both direct calls |

The forward tool is the authority for the matched rows and ABI states; the
different compiler inventories are expected and not a proof of semantic
equivalence. `Original-only` includes source/backend decisions such as
Crystal's constant-folded overload call; `Adamas-only` includes runtime
inventory. For the overload row the explicit `Parent#value(UInt64)` body is
present in Adamas while original LLVM folds that constant result, so the
unmatched identity is recorded rather than hidden. The generic ABI mismatch is
the known Box constructor representation difference and is outside this
identity-only slice.

The reachability classifier is intentionally conservative triage. For the
no-override rows it reports original 4 reachable definitions versus Adamas 7;
override is 5 versus 9; generic 5 versus 8; overload 5 versus 9. The derived
`reachable_unmatched_provisional` and `unreachable_provisional` fields are
preserved in the JSON manifest; they are not source-classified semantic extras
and neither authorizes pruning or a full liveness claim.

## IR and phase boundaries

The Adamas no-prelude reducer separately emits HIR/MIR and asserts one
ancestor body, zero child wrappers, and zero dispatcher for the empty
non-overriding matrix; the override case retains one dispatcher. The original
runtime oracle intentionally does not emit HIR or MIR, so original HIR/MIR
parity is **unavailable**, not inferred. The seven fresh same-source LLVM pairs
provide phase-local shape evidence for every row: no-override rows keep one
Parent implementation with no Child body or vdispatch; the override keeps the
Child body and dispatcher; generic keeps no Box value wrapper; overload keeps
both explicit Parent overload bodies. These are not full semantic-equivalence
proofs.

Authoritative evidence:

- matching exit status for every matrix row above, including the checked
  overload result and dynamic override cast;
- Adamas HIR body identity and MIR candidate/dispatcher checks from
  `regression_tests/inherited_virtual_demand_amplifier_no_prelude.sh`;
- focused HIR/MIR specs;
- fresh same-source LLVM pairs and forward census for every row, recorded in
  the JSON manifest.

Provisional evidence:

- textual LLVM symbol/body-shape comparison (compiler mangling and constant
  folding differ);
- conservative reachability counts (not linker-equivalent liveness);
- binary digests and static function counts, which are inventory aids rather
  than liveness or semantic proofs.

Residual boundary: full-prelude LLVM equivalence, complete historical
function-count attribution, all generic/module alias edges, and s2b-to-s5b
bootstrap remain open. The canonical Landmark graph validator was absent at G0;
JSON parsing, required-field/path checks, and `git diff --check` are the
available packet-validation fallback.
