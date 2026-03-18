# Crystal V2 Bootstrap — TODO (Updated 2026-03-18)

## Current State
- **Branch**: `bootstrap-benchmark`
- **Latest commit**: `72bc8aef` — parse `pointerof(...)` as a single expression
- **Working tree**:
  - uncommitted stage2 stabilization in `src/compiler/hir/ast_to_hir.cr`
  - unrelated local diffs in `src/compiler/mir/hir_to_mir.cr` and `src/crystal_v2.cr` must stay out of the next commit
- **Known-good release stage1**: `/tmp/codex_stage1_release_exprfix`
- **Fresh release stage2 from that stage1**: `/tmp/codex_stage2_release_classfix`
- **Stage2 build time (stage1 compiler -> stage2 compiler)**: `178.41s`
- **Stage3 bootstrap**: **FAILS** after `1.06s` with `Bus error: 10`
- **Benchmark status**: blocked — stage2 compiler is still unstable and crashes before finishing stage3

### Completed In This Cycle
1. **Release-stage1 parser fix remains the clean bootstrap baseline**
   - commit `72bc8aef` is still the last committed state
   - known-good compiler: `/tmp/codex_stage1_release_exprfix`
   - it can build a fresh release stage2 compiler from the current source tree

2. **Source-backed enum/class/module recovery now hardens the stage2 HIR corridor**
   - `src/compiler/hir/ast_to_hir.cr` now reconstructs enum/class/module names from source text instead of trusting corrupted slice-backed AST fields on self-hosted stage2
   - tiny enum oracle on fresh debug stage2 now passes:
     ```bash
     env DEBUG_ENUM_PARSE_BODY=1 DEBUG_ENUM_ARENA=1 CRYSTAL_V2_STOP_AFTER_HIR=1 \
       scripts/timeout_sample_lldb.sh ... -- /tmp/codex_stage2_dbg_enumfallback6 \
       --no-prelude /tmp/tiny_enum_stage2.cr -o /tmp/tiny_enum_stage2_dbg_enumfallback6_out
     ```
     Result: `status=0`, `real 1.06s`
   - direct `--release src/compiler/hir/hir.cr` on a fresh debug stage2 no longer crashes immediately in `register_concrete_class`; it now runs until wrapper memory limits (`29.15s` @ 4 GB with tracing, `60.00s` @ 12 GB without tracing)

3. **Fresh release stage2 rebuild succeeds on the current tree**
   - command:
     ```bash
     /usr/bin/time -p env CRYSTAL_CACHE_DIR_STAGE2_RELEASE=/tmp/codex_cache_stage2_release_classfix \
       CRYSTAL_V2_PIPELINE_CACHE=0 CRYSTAL_V2_LLVM_CACHE=0 \
       scripts/timeout_sample_lldb.sh -t 1800 -m 40960 -s 8 -l 20 -n 12 --no-series \
       -o /tmp/codex_stage2_release_classfix_timeout \
       -- scripts/build_stage2_release.sh /tmp/codex_stage1_release_exprfix /tmp/codex_stage2_release_classfix
     ```
     Result: `status=0`, `real 178.41s`

4. **Stage3 is still blocked by a new self-hosted crash**
   - command:
     ```bash
     /usr/bin/time -p env CRYSTAL_CACHE_DIR_STAGE2_RELEASE=/tmp/codex_cache_stage3_release_classfix \
       CRYSTAL_V2_PIPELINE_CACHE=0 CRYSTAL_V2_LLVM_CACHE=0 \
       scripts/timeout_sample_lldb.sh -t 1800 -m 40960 -s 8 -l 20 -n 12 --no-series \
       -o /tmp/codex_stage3_release_classfix_timeout \
       -- scripts/build_stage2_release.sh /tmp/codex_stage2_release_classfix /tmp/codex_stage3_release_classfix
     ```
     Result: `status=138`, `real 1.06s`, `Bus error: 10`

---

## Task 1: Stabilize the remaining stage2 self-hosted crash [ACTIVE]
**Priority: HIGH — blocks stage3 bootstrap and real stage1-vs-stage2 benchmark**

### Problem
The latest `ast_to_hir` hardening moved the old `register_concrete_class` crash frontier, but the resulting release-stage2 compiler is still unstable:
- it still crashes on `regression_tests/stage2_pointerof_nested_call_parser_repro.cr`
- it still crashes almost immediately on stage3 self-bootstrap
- the remaining failure is timing-sensitive: parse tracing changes behavior

### Current Evidence
1. **Stage2 exact repro**
   ```bash
   bash regression_tests/stage2_pointerof_nested_call_parser_repro.sh /tmp/codex_stage2_release_classfix
   ```
   Result: `exit 138` / `Bus error: 10`

2. **Old immediate `register_concrete_class` crash moved**
   ```bash
   /usr/bin/time -p scripts/timeout_sample_lldb.sh -t 180 -m 12288 -s 5 -l 10 -n 8 --no-series \
     -o /tmp/codex_hir_phase4_nodbg -- /tmp/codex_stage2_dbg_phase4 \
     --release src/compiler/hir/hir.cr -o /tmp/hir_stage2_phase4_nodbg_out
   ```
   Result: no early `register_concrete_class` crash; wrapper kills it on memory limit after `real 60.00s`

3. **Stage3 self-bootstrap**
   ```bash
   /usr/bin/time -p env CRYSTAL_CACHE_DIR_STAGE2_RELEASE=/tmp/codex_cache_stage3_release_classfix \
     CRYSTAL_V2_PIPELINE_CACHE=0 CRYSTAL_V2_LLVM_CACHE=0 \
     scripts/timeout_sample_lldb.sh -t 1800 -m 40960 -s 8 -l 20 -n 12 --no-series \
     -o /tmp/codex_stage3_release_classfix_timeout \
     -- scripts/build_stage2_release.sh /tmp/codex_stage2_release_classfix /tmp/codex_stage3_release_classfix
   ```
   Result: `status=138`, `real 1.06s`

4. **Heisenbug boundary on the exact repro**
   - `CRYSTAL_V2_STOP_AFTER_PARSE=1` on release stage2 often still bus-errors immediately
   - `CRYSTAL_V2_PARSE_TRACE=1 CRYSTAL_V2_STOP_AFTER_PARSE=1` makes the same compile survive and emit full parse logs
   - `CRYSTAL_V2_PARSE_TRACE=1 CRYSTAL_V2_STOP_AFTER_MIR=1` still bus-errors quickly; PTY output only reaches:
     ```text
     [PARSE] /Users/sergey/Projects/Crystal/crystal_v2_repo/src/stdlib/prelude.cr
     ```

### What To Debug Next
1. Keep `regression_tests/stage2_pointerof_nested_call_parser_repro.sh` as the primary cheap oracle before another full stage3 attempt
2. Compare stage2 behavior on the exact repro with and without `CRYSTAL_V2_PARSE_TRACE=1`
3. Narrow the new frontier inside `src/stdlib/prelude.cr` parsing / early front-end setup
4. Only return to the remaining enum slice-backed fallbacks if the new evidence points back into the same corridor

---

## Task 2: Finish benchmark once stage3 is stable [BLOCKED on Task 1]
Goal:
1. stage1 compiler builds stage2
2. stage2 compiler builds stage3
3. compare stage2-build time vs stage3-build time

Current measurable data:
- stage1 compiler -> current stage2 compiler: `178.41s`
- stage2 compiler -> stage3 compiler: **not yet measurable** (current binary crashes after `1.06s`)

---

## Task 3: Finish the remaining enum hardening sweep if the crash points back there [BACKLOG]
Subagent review found that the obvious top-level enum reads are now source-first, but the enum corridor is not fully clean yet:
- `enum_name_from_node`, `enum_base_type_name_from_node`, and `enum_member_name_from_node` still contain `safe_slice_to_string(...)` fallbacks
- `resolve_enum_member_value` still has original-AST value fallbacks
- some lazy / macro / lowering-time enum registration sites still build names from slice-backed fields

This is useful follow-up only if the new self-hosted crash walks back into enum registration. Do not mix it into the active parse-heisenbug investigation without new evidence.

---

## Task 4: Revisit union/layout inconsistency after bootstrap stability [BACKLOG]
Historical note from the previous frontier:
- `union_all_reference_types?` / HIR-vs-MIR all-ref-union handling is still conceptually inconsistent
- changing HIR struct handling still regresses `array_concat_string_runtime` and `test_generics_stack`
- current bootstrap blocker is no longer that path, so do **not** mix that work into the active stage2 crash investigation unless new evidence points back there

---

## Build Commands Reference
```bash
# Build stage1 (Crystal compiling V2 compiler)
crystal build src/crystal_v2.cr -o bin/crystal_v2 --error-trace

# Build stage2 (V2 compiler compiling itself)
bin/crystal_v2 src/crystal_v2.cr

# Run regression tests
bash regression_tests/run_all.sh          # 69 individual tests
bash regression_tests/run_all_suites.sh   # both suites (69 + 20 combined)

# Run single test safely
bin/crystal_v2 /tmp/test_hello.cr
scripts/run_safe.sh /tmp/test_hello 5 512

# Generate LLVM IR for comparison
CRYSTAL_V2_EMIT_IR=/tmp/test_ir.ll bin/crystal_v2 some_test.cr
```

## Key Files
- `src/compiler/hir/ast_to_hir.cr` — HIR lowering (72k lines, main file being modified)
  - `union_all_reference_types?` at ~line 27409
  - `field_storage_size` at ~line 27532
  - `type_size` at ~line 27323
  - `align_all_class_ivars` at ~line 19324
  - `hir_union_ivar_storage_size` at ~line 27442
- `src/compiler/mir/hir_to_mir.cr` — MIR lowering
  - `container_elem_storage_size_u64` at line 722
  - `lower_pointer_add` at line 5220
  - `lower_pointer_load` at line 5158
  - `lower_pointer_store` at line 5184
  - `register_class_types` at line 391
  - `all_ref_union_descriptor?` at line 673
  - `convert_type` at line 5482 (HIR→MIR type ID mapping, +20 offset for user types)
- `src/compiler/mir/llvm_backend.cr` — LLVM IR emission
  - `container_elem_storage_size_u64` at line 815
  - `emit_gep_dynamic` at line 11046 (use_byte_gep logic at line 11178)
  - `is_all_ref_union?` at line 128

## IMPORTANT RULES
- **Fix root causes, NOT symptoms** — no hardcoding, no workarounds
- **One feature/bugfix = one commit**
- **NEVER modify stdlib files** — must be 100% compatible with original Crystal stdlib
- **Always test**: `scripts/run_safe.sh <binary> <timeout> <max_mem_mb>` (NEVER run directly)
- **V2 ABI**: ALL Crystal structs are heap-allocated as pointers. C lib structs are inlined.
