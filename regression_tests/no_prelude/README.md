# No-Prelude Reducer Tier

Fast compiler reducers. Every `*.cr` here is compiled with `--no-prelude`,
so each test pays ~80ms instead of the ~16s full-prelude floor. Runner:
`regression_tests/run_no_prelude.sh`.

## When a test belongs here

A test fits this tier when its coverage target is **compiler behavior** that
can be triggered with a minimal `--no-prelude` source:

- HIR lowering (interpolation, casts, blocks, yield, Proc literals, closures)
- MIR generation / dispatch / arena management
- LLVM codegen / ABI / vdispatch tables
- Type system edges that surface without stdlib constructors

A test does **not** belong here when it probes stdlib/prelude semantics such
as `Hash` entry layout, `String::Builder#@bytesize`, `Fiber`/`Channel`
scheduling, `Exception` / `CallStack` unwinding, or `IO::FileDescriptor`
lifecycle. Those go to `regression_tests/combined/` (prelude-integration
bundles) or stay as standalone `regression_tests/*.cr`.

## Rules for a reducer

- **Self-contained.** The source must compile under `--no-prelude` without
  referencing types/methods that do not exist in that mode. (Example of
  something that breaks: `Float#**` — returns a wrong value under
  `--no-prelude`.)
- **Minimal output.** `puts` / `print` is available under `--no-prelude` and
  is the smallest portable way to signal PASS. Do not reach for
  `LibC.write` unless `puts` would obscure the bug.
- **Preserve the original signal.** If the bug manifests as a specific
  crash, stdout line, or exit code in the full-prelude original, the
  reducer must preserve that exact signal.
- **One focused scenario per file.** Keep each reducer narrow so a golden
  mismatch points at a single regression.
- **Strict golden by default.** Generate a sibling `<name>.out` with the
  exact expected stdout. The runner uses byte-exact `cmp` when the golden
  exists; the `# EXPECT: <substring>` header is the fallback only when a
  golden does not fit (e.g. nondeterministic output — rare here).

## Relationship to other tiers

| Tier                         | Compile flag   | Typical compile | What it guards |
|------------------------------|----------------|-----------------|----------------|
| `no_prelude/`                | `--no-prelude` | ~80ms           | Compiler lowering / codegen on minimal input |
| `combined/` (tiny bundle)    | full prelude   | ~16.4s × 1      | Bundled full-prelude scenarios (one prelude pays for many sections) |
| `combined/test_no_prelude_*` | `--no-prelude` | ~80ms           | Legacy location for stdlib contract oracles — prefer this dir for new reducers |
| `regression_tests/*.cr`      | full prelude   | ~16.4s × N      | Legacy per-file coverage — being migrated into the tiers above |

## Running just this tier

```bash
regression_tests/run_no_prelude.sh bin/crystal_v2 4
```

Exit 0 on PASS, 1 on FAIL. Runs in ~1s wall at parallelism 4.

## Adding a new reducer

1. Write the `.cr` file. Make it tiny.
2. Compile: `bin/crystal_v2 --no-prelude regression_tests/no_prelude/<name>.cr -o /tmp/probe`
3. Run: `scripts/run_safe.sh /tmp/probe 5 256`
4. Capture the expected stdout into `regression_tests/no_prelude/<name>.out`.
5. Add a `# EXPECT:` line in the `.cr` as a readable hint (runner prefers the
   golden, but the header documents intent).
6. Verify: `regression_tests/run_no_prelude.sh bin/crystal_v2` → PASS.
7. If the reducer supersedes a full-prelude original, do **not** delete or
   superseded the original in the same commit. Prove equivalence over a
   few runs first; a later commit can add it to a tier manifest.
