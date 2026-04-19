# Codex status — regression throughput branch

Date: 2026-04-19
Branch: `regression-throughput-no-prelude`

## Current HEAD

- `5d2db70b perf(tests): add no-prelude reducer tier — first 5 fast compiler reducers`
- Includes:
  - `c50d88df` tiny-primitives combined bundle,
  - `49e76db1` strict golden + superseded-originals manifest,
  - `5d2db70b` no-prelude reducer tier.

## Review-comment status

Old review comments about `test_tiny_primitives_bundle.cr` adding coverage but not saving time are stale on this branch:

- `regression_tests/combined/superseded_originals.txt` exists and lists 11 originals.
- `regression_tests/run_all.sh` reads that manifest and skips the listed originals before running the root regression set.
- `regression_tests/combined/test_tiny_primitives_bundle.out` exists and is used by `run_combined.sh` strict mode, so the final marker is not the only assertion.

## Verification run

- `crystal build src/crystal_v2.cr -o bin/crystal_v2 --error-trace` — green, only the known `Random::DEFAULT` warning.
- `regression_tests/run_no_prelude.sh bin/crystal_v2 4` — `5 passed, 0 failed`, `3s wall`.
- Tiny bundle strict check:
  - compiled `regression_tests/combined/test_tiny_primitives_bundle.cr`;
  - ran via `scripts/run_safe.sh`;
  - extracted stdout and compared byte-for-byte with `regression_tests/combined/test_tiny_primitives_bundle.out`;
  - result: `tiny_bundle_strict_ok`.
- Runner/manifest static checks:
  - `bash -n regression_tests/run_all.sh regression_tests/run_combined.sh regression_tests/run_no_prelude.sh regression_tests/run_all_suites.sh`;
  - manifest has `11` entries and `0` missing paths.

## Boundary

Full `run_all_suites.sh` was not run in this Codex pass because it intentionally triggers many full-prelude compiles. The targeted checks cover the two throughput mechanisms that were under review:

1. no-prelude tier is fast and green;
2. combined tiny bundle both saves suite time (root originals skipped) and has strict output coverage.

## Next useful work

If continuing this branch, the next throughput win is more batching, not more no-prelude conversions. Phase 3 Part A already found that most reducers rely on stdlib/prelude behavior. Candidate task: create the next combined bundle from another cluster of small, standalone full-prelude root tests, then add those originals to `superseded_originals.txt` only after a strict `.out` golden passes.

