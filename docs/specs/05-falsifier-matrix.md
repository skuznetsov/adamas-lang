# Crystal V2 Falsifier Matrix

> Status: Draft v0.1, 2026-05-08.
> Companion to: `docs/specs/*.md`, `TODO.md`, `LANDMARKS.md`.
> Format: each row maps a normative claim to the smallest known falsifier.

## 1. Status Legend

- `[FALSIFIABLE]`: guard exists or the falsifier command is explicit.
- `[FRONTIER]`: known boundary; not yet fixed.
- `[MISSING-FALSIFIER]`: claim is important but lacks a narrow guard.
- `[REFUTED]`: branch tried and recorded as not a valid fix.

## 2. Bootstrap Corridor

| ID | Claim | Source | Smallest Falsifier | Status |
|----|-------|--------|--------------------|--------|
| B1 | Produced stage must be built through `scripts/run_safe.sh`. | `00-bootstrap-contract.md` section 4 | Review/CI command check; direct produced binary execution is protocol violation. | [FALSIFIABLE] |
| B2 | A moved frontier is acceptable only with a guard and a named residual boundary. | `00-bootstrap-contract.md` section 5 | Commit lacks guard or TODO/LANDMARK boundary for a claimed fix. | [FALSIFIABLE] |
| B3 | Current no-prelude binary output crash after LLVM finalization is separate from static callee spelling. | LM-559 | `scripts/run_safe.sh <produced-s2> 60 4096 <static-call-reducer> --no-prelude -o <bin>` still exits 139 after LLVM finalizes output. | [FRONTIER] |

## 3. HIR Name Resolution

| ID | Claim | Source | Smallest Falsifier | Status |
|----|-------|--------|--------------------|--------|
| H1 | Qualified nested names must not duplicate owner segments. | `01-hir-name-resolution.md` section 2 | `regression_tests/p2_qualified_module_namespace_no_prelude.sh <compiler>` finds `Float::Float::ParsedNumberStringT` or duplicated `Float::FastFloat`. | [FALSIFIABLE] |
| H2 | Self-reopen wrappers must not recursively register the current owner. | `01-hir-name-resolution.md` section 2.2, LM-553 | `regression_tests/p2_self_nested_module_registration_frontier.sh <compiler>`. | [FALSIFIABLE] |
| H3 | Nested builtin annotations must remain top-level unless structurally nested. | `01-hir-name-resolution.md` section 3, LM-554 | `regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh <compiler>`. | [FALSIFIABLE] |
| H4 | Type-literal name queries lower to literal strings, not static stubs. | `01-hir-name-resolution.md` section 4, LM-558 | `regression_tests/p2_type_literal_name_query_no_stub.sh <compiler>`. | [FALSIFIABLE] |
| H5 | Function body presence must distinguish real bodies from stubs. | `01-hir-name-resolution.md` section 6 | Guard that creates a bodyless registered function and verifies downstream stages do not treat it as emitted. | [MISSING-FALSIFIER] |

## 4. Generic Template Registration

| ID | Claim | Source | Smallest Falsifier | Status |
|----|-------|--------|--------------------|--------|
| G1 | Generic/container fixes must not use arbitrary depth caps. | `02-generic-template-registration.md` section 2 | Static diff review plus a deep nested tuple/hash/array/proc oracle for any changed demand code. | [MISSING-FALSIFIER] |
| G2 | Empty or repeated generic owner names such as `Iterator::` or `Indexable::Indexable::...` are invalid. | `02-generic-template-registration.md` section 3 | Trace/IR guard that fails on empty owner suffixes or repeated owner joins in generated stage. | [MISSING-FALSIFIER] |
| G3 | Broad source-gated generic-template body scan is not an acceptable fix. | `02-generic-template-registration.md` section 5 | Reverted experiment regressed earlier around `Crystal::PointerLinkedList` / trace paths. | [REFUTED] |
| G4 | Produced `s2` full-prelude `puts 42` must get past current generic/template registration frontier. | `TODO.md`, LM-559 | `CRYSTAL_V2_TRACE_CLASS_FRONTIER=1 scripts/run_safe.sh <produced-s2> 60 4096 /tmp/hello.cr -o /tmp/hello_bin`. | [FRONTIER] |

## 5. MIR Call ABI

| ID | Claim | Source | Smallest Falsifier | Status |
|----|-------|--------|--------------------|--------|
| M1 | Exact static calls lower before receiver mutation. | `03-mir-call-abi.md` section 3 | `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh <compiler>` emits fallback `@func1` or wrong arity. | [FALSIFIABLE] |
| M2 | Receiver calls include a runtime receiver; static calls do not. | `03-mir-call-abi.md` section 4 | Static-call guard plus MIR shape check for receiver argument count. | [MISSING-FALSIFIER] |
| M3 | Null/missing HIR `TypeRef` is not an ordinary runtime object. | `03-mir-call-abi.md` section 6 | No-prelude MIR oracle covering a null `TypeRef` conversion path. | [MISSING-FALSIFIER] |
| M4 | Debug value-location metadata is opt-in during bootstrap and not semantic. | `03-mir-call-abi.md` section 7 | Build with metadata disabled and verify semantic guards still pass. | [FALSIFIABLE] |

## 6. LLVM Emission

| ID | Claim | Source | Smallest Falsifier | Status |
|----|-------|--------|--------------------|--------|
| L1 | LLVM backend must resolve MIR `FunctionId` to the named callee. | `04-llvm-emission.md` section 2, LM-559 | `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh <compiler>` rejects `@func1`. | [FALSIFIABLE] |
| L2 | LLVM calls must not have empty return type spelling. | `04-llvm-emission.md` section 3, LM-559 | Same guard rejects `call  @`. | [FALSIFIABLE] |
| L3 | Emitted IR for the static-call reducer must pass `llc` when available. | `04-llvm-emission.md` section 6 | Same guard runs `llc -filetype=obj` if `llc` exists. | [FALSIFIABLE] |
| L4 | Hardcoded IO overrides should use generated accessors instead of unstable offsets. | `04-llvm-emission.md` section 4 | Guard that changes/observes fd ivar layout and verifies IO overrides still emit correct fd load. | [MISSING-FALSIFIER] |

## 7. Refuted Branches

| ID | Branch | Evidence | Status |
|----|--------|----------|--------|
| R1 | Source-first generic type-param extraction as a broad fix. | Did not move the Float/ParsedNumberStringT frontier. | [REFUTED] |
| R2 | Caching `node.body` as a broad generic-template registration fix. | Did not move the frontier. | [REFUTED] |
| R3 | Source-gating generic-template nested-type body scan. | Failed earlier around `Crystal::PointerLinkedList` / trace paths. | [REFUTED] |
| R4 | Re-enabling source-backed top-level return annotations after LM-558. | Regressed produced `s2` full-prelude `puts 42` to earlier class registration crash around `class register idx=51/104`. | [REFUTED] |
