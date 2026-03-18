# Crystal V2 Bootstrap — TODO (Updated 2026-03-18)

## Current State
- **Branch**: `bootstrap-benchmark`
- **Latest commit**: `d84279ea` — recover HIR type names from source
- **Working tree**:
  - uncommitted stage2 parser-body stabilization in `src/compiler/frontend/parser.cr`
  - unrelated local diffs in `src/compiler/mir/hir_to_mir.cr` and `src/crystal_v2.cr` must stay out of the next commit
- **Known-good release stage1**: `/tmp/codex_stage1_release_exprfix`
- **Fresh release stage2 baseline**: `/tmp/codex_stage2_release_classfix`
- **Fresh release stage2 from parser-body branch**: `/tmp/codex_stage2_release_bodyidx_fresh`
- **Stage2 build times (stage1 compiler -> stage2 compiler)**:
  - baseline HIR-name recovery tree: `178.41s`
  - parser-body scalarization branch: `223.19s`
- **Stage3 bootstrap**: **FAILS** after `2.26s` with `Segmentation fault: 11` on `/tmp/codex_stage2_release_bodyidx_fresh`
- **Benchmark status**: blocked — stage2 compiler is still unstable and crashes before finishing stage3

### Completed In This Cycle
1. **`parse_block_body_with_optional_rescue` now scalarizes transient body storage**
   - `src/compiler/frontend/parser.cr` no longer stores growable `ExprId` wrappers directly while collecting block bodies
   - the helper now stores raw `Int32` indexes during parsing and reconstructs `ExprId` values only once, after the final body size is known

2. **The parser-body fix is real on no-prelude parser-only oracles**
   - new reduced repro: `regression_tests/stage2_block_body_exprid_parser_repro.sh`
   - baseline broken stage2 still reproduces cleanly:
     ```bash
     for i in 1 2 3 4 5; do
       env CRYSTAL_V2_STOP_AFTER_PARSE=1 /tmp/codex_stage2_release_classfix \
         --release --no-prelude regression_tests/stage2_block_body_exprid_parser_repro.cr \
         -o /tmp/classfix_parse_noprelude_op10_$i
     done
     ```
     Result: `5/5` failed with `rc=138`
   - fresh parser-body stage2 now survives the same parser-only oracle:
     ```bash
     for i in 1 2 3 4 5; do
       env CRYSTAL_V2_STOP_AFTER_PARSE=1 /tmp/codex_stage2_release_bodyidx_fresh \
         --release --no-prelude regression_tests/stage2_block_body_exprid_parser_repro.cr \
         -o /tmp/bodyidx_fresh_parse_noprelude_op10_$i
     done
     ```
     Result: `5/5` passed with `rc=0`
   - the slightly larger reduced variant `/tmp/reduced_with_overflow0.cr` shows the same boundary:
     baseline `5/5 rc=138`, fresh parser-body stage2 `5/5 rc=0` with `--no-prelude + CRYSTAL_V2_STOP_AFTER_PARSE=1`

3. **Fresh release stage2 rebuild succeeds from the parser-body branch**
   - command:
     ```bash
     /usr/bin/time -p env CRYSTAL_CACHE_DIR_STAGE2_RELEASE=/tmp/codex_cache_stage2_release_bodyidx_fresh \
       CRYSTAL_V2_PIPELINE_CACHE=0 CRYSTAL_V2_LLVM_CACHE=0 \
       scripts/timeout_sample_lldb.sh -t 1800 -m 40960 -s 8 -l 20 -n 12 --no-series \
       -o /tmp/codex_stage2_release_bodyidx_fresh_timeout \
       -- scripts/build_stage2_release.sh /tmp/codex_stage1_release_exprfix /tmp/codex_stage2_release_bodyidx_fresh
     ```
     Result: `status=0`, `real 223.19s`

4. **The remaining crash frontier is now later HIR, not the reduced parser-only body path**
   - simple HIR-only control still fails immediately on the fresh parser-body stage2:
     ```bash
     for i in 1 2 3; do
       env CRYSTAL_V2_STOP_AFTER_HIR=1 /tmp/codex_stage2_release_bodyidx_fresh \
         --release /tmp/stage2_simple_one.cr -o /tmp/bodyidx_fresh_hir_simple_$i
     done
     ```
     Result: `3/3 rc=139`
   - fresh LLDB on that simple HIR control still stops in:
     ```text
     Crystal::HIR::AstToHir#register_extern_fun(...)+704
     ```
   - full compile of `/tmp/reduced_with_overflow0.cr` is still red on the fresh parser-body stage2 (`3/3 rc=139`), so the parser-body fix moved only the early parser corridor; it did not solve the remaining self-hosted HIR crash

5. **Stage3 remains blocked**
   - command:
     ```bash
     /usr/bin/time -p env CRYSTAL_CACHE_DIR_STAGE2_RELEASE=/tmp/codex_cache_stage3_release_bodyidx_fresh \
       CRYSTAL_V2_PIPELINE_CACHE=0 CRYSTAL_V2_LLVM_CACHE=0 \
       scripts/timeout_sample_lldb.sh -t 1800 -m 40960 -s 8 -l 20 -n 12 --no-series \
       -o /tmp/codex_stage3_release_bodyidx_fresh_timeout \
       -- scripts/build_stage2_release.sh /tmp/codex_stage2_release_bodyidx_fresh /tmp/codex_stage3_release_bodyidx_fresh
     ```
     Result: `status=139`, `real 2.26s`, `Segmentation fault: 11`

---

## Task 1: Stabilize the remaining stage2 self-hosted crash [ACTIVE]
**Priority: HIGH — blocks stage3 bootstrap and real stage1-vs-stage2 benchmark**

### Problem
The parser-body scalarization fixed a real reduced parser-only self-hosted crash, but the resulting release-stage2 compiler is still unstable:
- reduced no-prelude parser-only oracles are now green on the fresh stage2
- the fresh stage2 still crashes almost immediately once HIR runs
- stage3 self-bootstrap still dies before a usable benchmark can be taken

### Current Evidence
1. **Reduced parser-only boundary is now clean**
   ```bash
   bash regression_tests/stage2_block_body_exprid_parser_repro.sh /tmp/codex_stage2_release_bodyidx_fresh
   ```
   Result: `exit 0` / `not reproduced`

2. **Baseline broken stage2 still reproduces the same reduced parser-only crash**
   ```bash
   bash regression_tests/stage2_block_body_exprid_parser_repro.sh /tmp/codex_stage2_release_classfix
   ```
   Result: `exit 138` / `reproduced`

3. **Fresh stage2 still crashes as soon as HIR is allowed to run**
   ```bash
   env CRYSTAL_V2_STOP_AFTER_HIR=1 /tmp/codex_stage2_release_bodyidx_fresh \
     --release /tmp/stage2_simple_one.cr -o /tmp/bodyidx_fresh_hir_simple
   ```
   Result: `exit 139`

4. **Fresh LLDB on the simple HIR control**
   ```bash
   env CRYSTAL_V2_STOP_AFTER_HIR=1 lldb --batch -o run -o 'frame info' \
     -- /tmp/codex_stage2_release_bodyidx_fresh --release /tmp/stage2_simple_one.cr \
     -o /tmp/bodyidx_fresh_hir_simple_lldb_out
   ```
   Result: stops in `Crystal::HIR::AstToHir#register_extern_fun(...)+704`

5. **Stage3 self-bootstrap**
   ```bash
   /usr/bin/time -p env CRYSTAL_CACHE_DIR_STAGE2_RELEASE=/tmp/codex_cache_stage3_release_bodyidx_fresh \
     CRYSTAL_V2_PIPELINE_CACHE=0 CRYSTAL_V2_LLVM_CACHE=0 \
     scripts/timeout_sample_lldb.sh -t 1800 -m 40960 -s 8 -l 20 -n 12 --no-series \
     -o /tmp/codex_stage3_release_bodyidx_fresh_timeout \
     -- scripts/build_stage2_release.sh /tmp/codex_stage2_release_bodyidx_fresh /tmp/codex_stage3_release_bodyidx_fresh
   ```
   Result: `status=139`, `real 2.26s`

### What To Debug Next
1. Keep `regression_tests/stage2_block_body_exprid_parser_repro.sh` as the cheap parser-only control for future parser experiments
2. Instrument or isolate `register_extern_fun` on the fresh parser-body stage2, especially `node.params`, `Parameter#type_annotation`, and the local `Array(TypeRef)` build path
3. Test whether reparsing lib bodies from source changes the `register_extern_fun` crash frontier
4. Only return to broader parser-body scalarization sites if new evidence shows the active crash is still in the same family

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
