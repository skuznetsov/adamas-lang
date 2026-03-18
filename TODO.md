# Crystal V2 Bootstrap — TODO (Updated 2026-03-18)

## Current State
- **Branch**: `bootstrap-benchmark`
- **Latest commit**: `92f5774f` — field_storage_size C lib struct exclusion
- **Working tree**: parser fix + new regression repro are uncommitted
- **Fresh stage1 (original Crystal `--release`)**: `/tmp/codex_stage1_release_pointerof_fix`
- **Fresh stage1 build time**: `566.25s`
- **Stage1 regressions**: `70/70` + `20/20` combined
- **Stage2 bootstrap**: **SUCCESS** — `/tmp/codex_stage2_release_pointerof_fix`
- **Stage2 build time (stage1 compiler -> stage2 compiler)**: `248.42s`
- **Stage3 bootstrap**: **FAILS** after `2.04s` with `Segmentation fault: 11`
- **Benchmark status**: blocked — stage2 compiler is still unstable and crashes before finishing stage3

### Completed In This Cycle
1. **Release-stage1 parser crash fixed**
   - Old failure: fresh release-stage1 crashed immediately while compiling `src/compiler/hir/ast_to_hir.cr`
     with stack `parse_prefix -> parse_pointerof -> parse_op_assign -> parse_parenthesized_call`
   - New exact repro:
     - source: `regression_tests/stage2_pointerof_nested_call_parser_repro.cr`
     - script: `regression_tests/stage2_pointerof_nested_call_parser_repro.sh`
   - Key reduction:
     - baseline exact repro crashed on old stage1
     - replacing `pointerof(offset)` with `offset` made it pass
     - collapsing the long call to `register_class_members_from_expansion(class_name)` made it pass
   - Fix applied in `src/compiler/frontend/parser.cr`:
     - `parse_pointerof` now parses exactly one argument via `parse_op_assign`
     - removed the generic `parse_expression(0)` loop for multiple args
   - Verified results on fresh release-stage1:
     - exact repro: passes
     - `src/compiler/hir/ast_to_hir.cr`: passes
     - full regressions: `70/70 + 20/20`
     - stage2 self-bootstrap: passes

---

## Task 1: Fix stage2 `register_concrete_class` crash [ACTIVE]
**Priority: HIGH — blocks stage3 bootstrap and real stage1-vs-stage2 benchmark**

### Problem
Stage2 now builds successfully, but the resulting stage2 compiler is still unstable:
- it crashes on `regression_tests/stage2_pointerof_nested_call_parser_repro.cr`
- it crashes on `src/compiler/hir/ast_to_hir.cr`
- it crashes almost immediately on stage3 self-bootstrap

### Current Evidence
1. **Stage2 exact repro**
   ```bash
   bash regression_tests/stage2_pointerof_nested_call_parser_repro.sh /tmp/codex_stage2_release_pointerof_fix
   ```
   Result: `exit 138` / `Bus error: 10`

2. **Stage2 direct file compile**
   ```bash
   /tmp/codex_stage2_release_pointerof_fix --release src/compiler/hir/ast_to_hir.cr -o /tmp/codex_ast_to_hir_stage2_pointerof_fix.bin
   ```
   Result: `exit 138`

3. **Stage3 self-bootstrap**
   ```bash
   /usr/bin/time -p env CRYSTAL_CACHE_DIR_STAGE2_RELEASE=/tmp/codex_cache_stage3_release_pointerof_fix \
     CRYSTAL_V2_PIPELINE_CACHE=0 CRYSTAL_V2_LLVM_CACHE=0 \
     scripts/timeout_sample_lldb.sh -t 1200 -s 8 -l 20 -n 12 \
     -o /tmp/codex_stage3_release_pointerof_fix_timeout \
     -- scripts/build_stage2_release.sh /tmp/codex_stage2_release_pointerof_fix /tmp/codex_stage3_release_pointerof_fix
   ```
   Result: `status=139`, `real 2.04`

4. **LLDB crash head on stage2 exact repro**
   - `Crystal::HIR::AstToHir#register_concrete_class(...)+10344`
   - bad address like `0xfc9dd5480000000a`

### What To Debug Next
1. Build a **debug** stage2 with isolated cache and rerun the exact repro under LLDB
2. Inspect `register_concrete_class` around the class-body / ivar-registration corridor
3. Compare stage1-vs-stage2 behavior in:
   - `collect_defined_instance_method_full_names`
   - `class_body.each_with_index`
   - `realign_registered_ivars`
   - initialize-parameter capture / ivar inference
4. Keep `regression_tests/stage2_pointerof_nested_call_parser_repro.sh` as the primary cheap oracle before another full stage3 attempt

---

## Task 2: Finish benchmark once stage3 is stable [BLOCKED on Task 1]
Goal:
1. stage1 compiler builds stage2
2. stage2 compiler builds stage3
3. compare stage2-build time vs stage3-build time

Current measurable data:
- stage1 compiler -> stage2 compiler: `248.42s`
- stage2 compiler -> stage3 compiler: **not yet measurable** (current binary crashes after `2.04s`)

---

## Task 3: Revisit union/layout inconsistency after bootstrap stability [BACKLOG]
Historical note from the previous frontier:
- `union_all_reference_types?` / HIR-vs-MIR all-ref-union handling is still conceptually inconsistent
- changing HIR struct handling still regresses `array_concat_string_runtime` and `test_generics_stack`
- current bootstrap blocker is no longer that path, so do **not** mix that work into the active stage2 crash investigation unless the new evidence points back there

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
