# Plan: Inline Structs for V2 (Path B)

## Problem
V2 heap-allocates ALL Crystal structs as pointers (`when .struct? then "ptr"`).
This creates: field offset divergence, GC corruption, broken copy semantics,
performance degradation, and is the root cause of stage2 failures.

## Goal
Match the original Crystal compiler's struct handling:
- Structs are stored INLINE (value types) in class fields, arrays, tuples
- Classes are stored as POINTERS (reference types)
- C structs are already inline (via @lib_structs)

## Reference: Original Crystal (llvm_typer.cr)
```crystal
def create_llvm_type(type : InstanceVarContainer, wants_size)
  final_type = llvm_struct_type(type, wants_size)  # inline struct
  unless type.struct?
    final_type = final_type.pointer  # ONLY classes get pointer
  end
  final_type
end
```

## Changes Required

### Phase 1: LLVM Type Mapper (llvm_backend.cr)
- [ ] `compute_llvm_type_for_type`: struct → inline LLVM struct type
- [ ] `compute_llvm_type_for_type`: tuple → inline LLVM tuple type
- [ ] New: `compute_struct_llvm_type(type)` → builds `{ field1_type, field2_type, ... }`
- [ ] Handle recursive struct types (forward declarations)

### Phase 2: Field Access (llvm_backend.cr)
- [ ] `emit_field_get`: for struct fields, GEP directly to inline offset
  - BEFORE: GEP → load ptr → dereference
  - AFTER: GEP → load inline value
- [ ] `emit_field_set`: store inline value, not pointer
- [ ] Struct copy semantics: assignment = memcpy, not pointer copy

### Phase 3: Constructors (llvm_backend.cr + ast_to_hir.cr)
- [ ] Struct `.new`: alloca on stack, not __crystal_v2_malloc64
- [ ] Struct initialize: write fields inline
- [ ] field_storage_size: return INLINE size for structs (not pointer size)
  - Revert the `< pointer_word_bytes` → `!= pointer_word_bytes` change

### Phase 4: Function Calling Convention
- [ ] Struct args: pass by value (small structs) or by ptr+copy (large)
- [ ] Struct returns: return by value (small) or sret (large)
- [ ] Original Crystal threshold: structs > 2 words passed by pointer

### Phase 5: Array/Container Storage
- [ ] Array(Struct): elements stored inline (stride = struct size)
- [ ] Pointer(Struct)#value: returns inline struct copy
- [ ] Pointer(Struct)#value=: stores inline struct

### Phase 6: Union Handling
- [ ] Union containing struct: payload must fit struct inline size
- [ ] Union wrap/unwrap: copy struct value, not pointer

### Critical: Primitive Values in Compound Structs
The struct-as-pointer ABI causes `false` and `0` to be stored as null pointers
inside Tuples, NamedTuples, and other compound types. When code dereferences these
pointers to read the primitive value, it crashes (null deref at address 0x0).

**Proven crash path (2026-04-03):**
- `pack_splat_args_for_call` returns `Tuple(Array(ValueId), Bool)`
- V2 heap-allocates the tuple, stores `Bool false` as `inttoptr 0` (null ptr)
- Tuple unpacking loads ptr from offset 16, dereferences → crash at `ldr w9, [x13]` where x13=0

**This subsection MUST be addressed before or alongside Phase 1:**
- Primitive elements (Bool, Int32, Float64, etc.) inside Tuples/NamedTuples/Structs
  must be stored as their native LLVM types (i1, i32, double), not as ptr
- `false` must be `i1 0`, not `ptr null`
- `0_i32` must be `i32 0`, not `ptr null`
- This is independent of whether the containing struct is inline or heap-allocated

## Testing Strategy
- Run regression tests after each phase
- Compare stage1 vs stage2 HIR/MIR for oracle programs
- Must maintain 87/88 + 18/20 test score

## Risk Mitigation
- C structs (@lib_structs) are ALREADY inline — don't change
- Reference types (classes) keep their pointer semantics — don't change
- Enums keep their i32 semantics — don't change
- Start with Phase 1 (type mapper) and run tests before continuing
