# AN ordinary bootstrap verification

The same sealed AN source builds the ordinary S1 -> S2 -> S3 -> S4 ladder.
S3 and S4 reach a fixed point in complete raw emitted LLVM IR and executable
code/data. No IR rewriting or GCX was used. The source snapshot contains 1,919
Git-tracked source files; its manifest SHA-256 is
`8994a713ac889fccbadfdc0c44fae3583ec760f281a1ceae3bc4d9c634d55a1c`.
The runtime manifest SHA-256 is
`4fa3ee9b09ea00079af693d7589504b17855ee0fa5d323380e152b07b4cd76e3`.
These results use the repository's bundled stdlib and default environment;
external-stdlib substitution needs separate verification.

## Build and fixed point

| Stage | Build time | Executable SHA-256 |
| --- | --- | --- |
| S1 | 18.84 s | `d9fc4c3e999ea442e3f028bc4d61897509707b3400a3f10f5f6173526bf8c3e4` |
| S2 | 491.13 s | `a58558722b20f088a898d739fcf101201afe8115e04861f97709dd241453afc0` |
| S3 | 545.59 s | `f9482f8e77e3419db7f506446e6d02d89bee75bb9eefc7db16e90af55a570e8d` |
| S4 | 589.59 s | `b9e7e330bc2c38f35c8e500f81843b09b2dbf32f885f98fe39531e19a5718ef8` |

S4 was built by S3 with `--no-llvm-cache`, through `scripts/run_safe.sh` with
a 900-second deadline and 12,288 MiB memory cap. It exited 0, with observed
peak RSS 6,557,488 KiB and peak FD count 18. All source and runtime seals stayed
unchanged before and after the build.

The complete raw `s3_an.ll` and `s4_an.ll` files are byte-identical, without
normalization: 261,848,465 bytes each and SHA-256
`a4abf17e54303af30027f5b4a16fdf447869e28f1c7683f5b6783cfbd79a2ee3`.
Actual `cmp -s` and full `diff -u` both returned 0; the diff is empty.

All 11 Mach-O sections have identical layout and contents. Every executable
byte outside the parsed UUID and ad-hoc code-signature payload ranges is
identical. Whole-file executable identity is false: the 53 differing bytes
are 16 UUID bytes and 37 signature bytes (5 identifier bytes and 32 first-page
hash bytes). The signature identifier includes the output stage name and
process ID. These differences do not touch code or data sections.

The proportionate read-only adversary check returned **ROBUST** for this
pair-specific result. The historical S3 receipt sealed its executable, not
its LLVM IR at emission time; the LLVM hashes above are current artifact
observations. Executable code/data equality independently corroborates the
fixed-point result.

## Runtime and packaging checks

- S1 and S3: the exact 164-script [selected manifest](../regression_tests/bootstrap_an_manifest.md), each with 589 supervised calls, no script drift or abnormal resource outcomes.
- S2: 15 focused scripts plus the separate inherited-layout gate.
- S3: four enum/Regex checks and the separately receipted native-realloc contract.
- S2/S3/S4: three exact-output runtime smokes each; both strict rejection guards pass S1/S2/S3.
- Commit preparation: all six changed/new HIR, LSP and MIR spec files pass: 119 examples, 0 failures, 0 errors, 0 pending.
- Follow-up WIP coverage: eleven additional regression entry points pass fourteen S4 cases, and two additional HIR spec files pass seven examples. See the [follow-up coverage and receipts](bootstrap_an_wip_regressions.md); this does not widen the earlier S1/S3 suite claim.

Every compiler and test binary was supervised by `scripts/run_safe.sh`.
The source bytes were preserved during packaging; documentation updates do
not alter the source or runtime seals. The modified compiler files combine
the imported Claude bootstrap corrections and the independently tested
rescue fixes; staging only the earlier session-owned patch would omit part
of the AN state.

## Evidence and remaining scope

The prior S1-S3 checkpoint is indexed by
`.landmark/evidence/2026-10-13-claude-bootstrap-rescue.json`; the S4 follow-up
is `.landmark/evidence/2026-10-13-an-s4-fixed-point.json`.
Captured artifacts and receipts are under
`/Users/sergey/Projects/Adamas/sol_help_20261012`, including
`s4_an.receipt.json`, `s3_s4_an.comparison.json`, `s3_s4_an.ll.diff`,
`s3_s4_an.byte_differences.json`, `s4_an_smokes/results.json` and
`integration_an/changed_specs.receipt.json`.

This establishes the declared bootstrap and selected runtime milestone.
General block-splat and multiple-yield `typeof` inference, raw-pointer struct
storage/value copying, collector/finalizer capability, and full Crystal
compatibility remain separate frontiers. The reason ClassInfo was absent at
the earlier annotation-guess consumption point is still unknown.
Changes to relevant source, hierarchy registry, runtime, toolchain, environment
or fixtures invalidate dependent evidence and require the affected checks
again. The earlier evidence packet remains an immutable historical checkpoint.
