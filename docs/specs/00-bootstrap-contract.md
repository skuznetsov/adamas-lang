# Crystal V2 Bootstrap Contract

> Status: Draft v0.1, 2026-05-08.
> Companion to: `TODO.md`, `LANDMARKS.md`, and `regression_tests/`.
> Scope: stage-to-stage semantic equivalence for the active `codegen` branch.

## 1. Purpose

Crystal V2 exists to reach a clean compiler bootstrap corridor:

```text
original -> stage1 -> s2b -> s3b -> s4b -> s5b
```

The contract is not "match every internal detail of the original compiler".
The contract is:

1. Preserve Crystal source semantics.
2. Preserve normalized HIR/MIR/LLVM meaning across generated stages.
3. Keep bootstrap progress falsifiable with small, reproducible guards.

The near-term integration gate is `s1 -> s2b`. Longer chains are expensive and
SHOULD run only after the near-term gate is clean.

## 2. Stage Definitions

| Stage | Meaning |
|-------|---------|
| `original` | The upstream Crystal compiler used as source semantic oracle. |
| `stage1` | Host-built `src/adamas.cr` compiler. |
| `s2b` | Compiler produced by `stage1` from `src/adamas.cr`. |
| `s3b+` | Later self-hosted compilers produced by the previous generated stage. |

`stage1` and generated stages MAY differ in debug metadata, temporary symbol
ordering, and non-semantic comments. They MUST NOT differ in source-visible
behavior, ABI shape, required symbol identity, or reachable runtime semantics.

## 3. Equivalence Model

### 3.1 Semantic Equivalence

Two stage outputs are semantically equivalent when the same Crystal input:

- accepts or rejects with the same class of diagnostic;
- has the same compile-time constants and type-literal results;
- emits calls to the same semantic callees;
- preserves class/module ownership and generic specialization identity;
- produces runtime behavior equivalent to the original compiler for the
  covered feature.

The original compiler is the source semantic oracle. A stage-to-stage guard is
not enough when a change touches language behavior. Such changes SHOULD include
an original-vs-stage oracle:

```bash
crystal <case>.cr --emit llvm-ir --no-link -o /tmp/original_case
<stage-compiler> <case>.cr --emit llvm-ir --no-link -o /tmp/stage_case
```

The comparison MUST normalize non-semantic ids and metadata before deciding
equivalence. If no normalizer exists for the feature, the guard must state the
specific semantic lines it compares.

Current B3 executable oracle:
`regression_tests/original_vs_stage_semantic_oracle_contract.sh <compiler>`.
It compares original Crystal and the supplied stage compiler on explicit
source-visible semantic lines:

- `TYPE=<typeof expression result>`;
- `CONST=<constant-folded arithmetic result>`;
- `UNION=<runtime class result for a nilable expression>`.

The current stage is measured-red for the type-visible lines; use
`ADAMAS_EXPECT_ORIGINAL_STAGE_MISMATCH=1` only to assert that known frontier,
not as an acceptance gate.

### 3.2 HIR Equivalence

Normalized HIR equivalence ignores:

- incidental numeric ids when the referenced entity is unchanged;
- stable debug-only metadata when disabled;
- function order if call graph and body ownership are unchanged.

It does not ignore:

- changed owner names;
- fake nested names such as `Float::Float::...`;
- missing function bodies;
- receiver/static call confusion;
- type-literal queries lowered as runtime class method calls.

### 3.3 MIR Equivalence

Normalized MIR equivalence ignores local SSA id spelling but not:

- callee `FunctionId`;
- receiver argument count;
- return type and union ABI;
- whether a call is static, virtual, extern, or intrinsic;
- whether a `Void`/`Nil` value is used as a real runtime object.

### 3.4 LLVM Equivalence

Normalized LLVM equivalence ignores comments, debug metadata when disabled, and
private string ids. It does not ignore:

- callee symbol name;
- empty or invalid return type spelling;
- ABI layout of unions, classes, structs, or slices;
- object size and alignment;
- link-visible declarations.

## 4. Gates

### 4.1 Fast Gates

Fast gates SHOULD be no-prelude and narrow. They exist to isolate one contract
family from the full stdlib.

Examples:

- `regression_tests/p2_qualified_module_namespace_no_prelude.sh`
- `regression_tests/p2_type_literal_name_query_no_stub.sh`
- `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh`

Fast gates that compare stage outputs SHOULD also state whether they compare
against the original compiler, `stage1`, produced `s2`, or all three.

### 4.2 Integration Gate

The main integration gate is:

```bash
crystal build src/adamas.cr -o /tmp/cv2_stage1 --error-trace
scripts/run_safe.sh /tmp/cv2_stage1 300 4096 src/adamas.cr -o /tmp/cv2_s2/cv2_s2
```

The produced compiler MUST then pass the fast guards relevant to the changed
contract family.

#### 4.2.1 Fresh Bootstrap Evidence Producer

`scripts/bootstrap_chain.sh` accepts only an absent run-directory path whose
existing parent resolves outside the source evidence scope. The producer
creates that directory and its initially empty compiler cache itself with mode
`0700`; an existing path, including an empty directory, is rejected. Adamas,
worker, and run-safe control overrides are rejected, while known generic
compiler/linker controls are removed before target launch. Hashes of the
remaining `PATH`, `HOME`, and `TMPDIR` context are recorded without persisting
their values.

Each stage output must be a new regular, nonempty, executable, single-link
file. Every generated stage records the hash of its producer before and after
the stage; stage N+1 is admitted only when that producer hash equals the prior
stage's stable output hash.

Each build is supervised with a new B7 resource receipt. Build logs, resource
receipts, smoke binaries, and exact plain/no-prelude runtime transcripts must
remain regular single-link files and are hashed into the producer-owned
`bootstrap_chain_v3` manifest. A final pass revalidates every successful-stage
artifact, B7 success receipt, and exact transcript immediately before manifest
publication. Source content, source-scope hashes, source symlink absence, and
run/cache directory identities are checked at the two endpoints. The manifest
is installed atomically without overwriting an existing path; collision fails
the chain.

This manifest is a compositional receipt, not a readiness verdict. A consumer
must rehash its referenced on-disk files, validate lineage and transcript
content, and apply performance/resource policy. T8 owns that offline decision.
The source certificate is explicitly endpoint consistency, not proof that no
mutate-then-restore event occurred, and it does not close all external stdlib,
toolchain, or same-UID hostile-writer inputs. Those contexts remain outside the
B6 producer claim and must not be inferred from a successful receipt.

#### 4.2.2 Offline Fresh-S2 Readiness Validator

`scripts/validate_bootstrap_manifest.sh --run-dir <dir> --expected-host <path>`
is the T8 consumer for one canonical two-stage B4-F run. The expected host is
an explicit trust input, not a manifest assertion. The validator is read-only
and requires the current source/git state and B6/B7 harness hashes to match the
receipt before consuming it.

Producer and consumer share the strict transcript, resource-row, and build-wall
parsers in `scripts/lib/bootstrap_evidence_contract.sh`; the producer records
that file's hash and the consumer rechecks it. This keeps acceptance grammar
from drifting across two independently edited parser copies.

For both stages it rehashes the normal executable, build log, producer-owned
B7 receipt, smoke binaries, compile logs, and exact runtime transcripts. It
also binds the producer-created `puts 42` source and the canonical repository
no-prelude oracle by path and hash, rejecting stale or symlinked smoke inputs.
It requires complete numeric rooted-ancestry RSS and FD coverage, successful
resource outcomes, producer lineage, producer-created run/cache identities,
normal build flags, and `CRYSTAL_WORKERS`-unset policy. Stage2 wall time must be
at most 300 seconds; exactly 300 seconds is admitted. Any mismatch rejects the
receipt without rerunning a generated compiler.

T8 is a decision procedure over a B6 receipt, not evidence that a current
receipt is green. B4-F remains open until a fresh current-source two-stage run
passes T8 with both semantic transcripts and numeric resource coverage. T8
inherits B6's non-hermetic boundary: trusting a host binary hash does not seal
external stdlib/toolchain files or same-UID hostile writers.

### 4.3 Runtime Gate

Any produced test binary MUST be executed through:

```bash
scripts/run_safe.sh <binary> <timeout> <mem_mb>
```

Direct execution of produced binaries is outside the test protocol.

## 5. Residual Frontier Tracking

A fix MAY be accepted when it moves a frontier and leaves a different frontier
open, but only if:

- the fixed invariant has a guard;
- the new boundary is named in `TODO.md` or `LANDMARKS.md`;
- the commit message states what is and is not fixed.

Current example: LM-559 fixes static callee and return ABI spelling, but
produced `s2` no-prelude binary output still exits 139 after LLVM finalizes
output. That is a separate CLI/file-output tail or outer-rescue frontier.

## 6. Resource Evidence Integrity

`scripts/run_safe.sh` is the sole owner of supervised process resource
evidence. It emits one diagnostic `[RUN_SAFE_RESOURCE]` row for a launched
target. When `RUN_SAFE_RESOURCE_FILE` names a new absolute path, the wrapper also
publishes exactly one producer-owned `run_safe_resource_v1` row there without
overwriting an existing path. A destination collision or publication race
makes the wrapper fail. Consumers MUST require wrapper success and use that
file, not captured target output, as the authoritative channel.

RSS maxima are admitted only when every scheduled RSS observation is a valid
`ps` point-snapshot of the visible ancestry rooted at the supervised target.
FD maxima additionally require `lsof` to name every PID with at least one
canonical FD row and a second `ps` topology fence to preserve the same
PID/PPID/process-group relation. Missing tools, malformed rows, partial PID
coverage, or a failed observation must produce `unknown` for the affected
metric; a partial-PID or empty probe must never be serialized as a tree-wide
numeric zero.

A sampling transaction that reaches a syntactically valid second `ps -axo`
response without the supervised root is aborted only when an independent
liveness check confirms that the root exited. It contributes no point or pair
to the published counters, so an incomplete natural-exit fence cannot
invalidate earlier completed samples. If the root is still live, or the fence
is malformed or failed, the observation remains unstable and fails FD evidence
closed.

The row records the outcome, reason, exit code, per-metric sample counts,
coverage, observation mode, and maximum observed ancestry width. It is sampled
evidence over the visible rooted ancestry, not a hermetic resource proof:
detached or reparented processes and between-sample spikes remain outside the
certificate. When probes are unavailable, the wall-clock watchdog and target
process-group cleanup remain active, but aggregate RSS/FD cap enforcement is
not certified. Evidence decays when the supervisor, process-probe availability,
sampling interval, or process ownership changes. Refresh it with the B7
falsifier before consuming it in bootstrap readiness evidence.
