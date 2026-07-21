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

### 4.2.1 Fresh-s2 readiness classifier

`scripts/t8_fresh_s2_readiness_validator.sh` is the executable T8 classifier
for the fresh `s1 -> s2b` vector. It allocates fresh output/private-cache
scope and records source/patch provenance, artifact path/hash evidence, exact
runtime transcripts, integer-millisecond wall reports, and resource reports
when present. Its receipt uses schema `t8_fresh_s2_v1` and reports
`T8_STATUS`/`T8_CLASSIFICATION`.

Only `T8_STATUS=GREEN` with both exact smoke outputs, `stage2_wall_ms <=
180000`, and complete resource evidence is a readiness certificate. Missing or
partial resource telemetry is `RESOURCE_UNKNOWN`; reused, symlinked, or
contradictory provenance/artifacts are `ERROR`; timeout, over-budget, or
semantic smoke failures are measured red. T8 classifies the gate; it does not
promote B4-F without producer-owned provenance, artifact, resource, and timing
authority.

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
