# Crystal V2 Bootstrap — TODO (Updated 2026-03-22)

## Current Status
- **Branch**: `bootstrap-benchmark` (merged `inline-structs`)
- **Regression tests**: 87/88 + 18/20 (stable, no regressions)
- **Stage2 binary**: compiles but LLC fails on `ptr 0` — ALMOST FIXED

## IMMEDIATE: Fix `ptr 0` → `ptr null` in stage2 LLC

### Done:
- `emit_select`: normalizes ptr 0 → ptr null ✓
- `emit` helper: gsub normalization ✓
- `emit_raw`: gsub normalization ✓
- Worker temp file output (IO.copy): normalization ✓
- Parent output (IO.copy): normalization ✓ (just added, **UNTESTED**)

### Test:
```bash
crystal build src/crystal_v2.cr -o bin/crystal_v2 --error-trace
bin/crystal_v2 src/crystal_v2.cr -o /tmp/crystal_v2_s2
# Should compile without LLC error
```

If `ptr 0` still appears, check `emit_toplevel` (@output << s at line ~2571).

## NEXT: Test Stage2 Oracle

Once stage2 compiles without LLC error:
```bash
echo '42' > /tmp/test.cr
CRYSTAL_V2_STOP_AFTER_MIR=1 /tmp/crystal_v2_s2 /tmp/test.cr -o /tmp/out --no-prelude --emit hir
# Expected: literal 42 : Int32 (NOT literal nil)
```

- `Literal` has `int_value`/`float_value` primitive bypass fields
- `Literal#to_s` uses `@type`-based dispatch (not `@value` union)
- `lower_number` sets `lit.int_value = node.parsed_int`
- `NumberNode.parsed_int` pre-parses at constructor time

## ROOT CAUSES FOUND

### 1. Union tag stripping (CRITICAL, partially fixed)
- `llvm_backend.cr:14226-14235`: extracts union PAYLOAD, drops TAG
- `llvm_backend.cr:2599-2605`: same in fixup_call_arg_types
- Fixed: pass ptr to full union alloca
- But callee wraps ptr as `{tag=0, payload=ptr}` → still Nil
- **Full fix needed**: pass unions by value or memcpy on callee side

### 2. Struct-as-pointer ABI (ARCHITECTURAL, plan exists)
- `llvm_backend.cr:236`: `when .struct? then "ptr"`
- All structs heap-allocated as pointers
- Should be inline (value types) like original Crystal
- See `PLAN_INLINE_STRUCTS.md`

### 3. Dangling struct pointers (WORKAROUND applied)
- Slice/Span heap objects freed between parse and HIR lowering
- Workaround: NumberNode.parsed_int/parsed_float + Literal.int_value/float_value

## STAGE2 WORKAROUNDS (10 bypasses in cli.cr)
1. File.exists? → LibC.access
2. File.read → LibC.open/read/close
3. File.open → LibC.open + IO::FileDescriptor
4. Pipeline cache: DISABLED
5. AST cache: DISABLED
6. Set constants → case/when
7. SHA256 → FNV-1a
8. flag?/has_constant? → return false
9. Object#==(T) → return false
10. Void→Nil forwarding for Hash methods

## KEY FILES MODIFIED THIS SESSION
- `src/compiler/frontend/ast.cr` — NumberNode: parsed_int/parsed_float
- `src/compiler/hir/hir.cr` — Literal: int_value/float_value, @type-based to_s
- `src/compiler/hir/ast_to_hir.cr` — lower_number; field_storage_size; safe_set_includes
- `src/compiler/mir/hir_to_mir.cr` — FieldGet/FieldSet inline; hir_type_is_struct? generic
- `src/compiler/mir/llvm_backend.cr` — ptr 0→null; union arg fixes; Set→case/when
- `src/compiler/cli.cr` — LibC file ops; cache disable; trace points
