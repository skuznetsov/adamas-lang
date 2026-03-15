# Plan: Implement rc_dec + Fix FFIExposed Strategy

## Context

The Crystal v2 compiler's ARC system is half-built: `rc_inc` is emitted at allocation
time, but `rc_dec` is never emitted anywhere. All ARC-managed objects leak.
Additionally, `FFIExposed` values are unnecessarily routed to GC.

The infrastructure is fully ready — only the call sites are missing.

## Pre-requisites

- 68/68 regression tests pass (confirmed 2026-03-15)
- No code changes needed in mir.cr, llvm_backend.cr, or the runtime
- All changes are in `hir_to_mir.cr` and `memory_strategy.cr`

---

## Task 1: Fix FFIExposed Memory Strategy

**File:** `src/compiler/hir/memory_strategy.cr`

**Problem:** Lines 230 and 274 treat `FFIExposed` the same as `Cyclic`:
```crystal
if taints.cyclic? || taints.ffi_exposed?
  return MemoryStrategy::GC
end
```

**Why it's wrong:** Most FFI calls are borrows — C reads/copies data, Crystal keeps
ownership. Defaulting to GC loses deterministic cleanup for no reason.

**Fix:** Remove `taints.ffi_exposed?` from the GC guard. FFIExposed values continue
through the normal escape/taint decision tree (ARC if escaping, Stack if local).

The `@[Transfer]` annotation (already parsed in ast_to_hir.cr:3459-3460 and stored
in `MethodEffectSummary.transfer`) handles the rare case where C takes ownership.
When `transfer == true`, the taint propagation already marks args with
`LifetimeTag::ArgEscape` (escape_analysis.cr:186-189), and on the Crystal side
we should NOT emit rc_dec (C owns it now).

**Changes:**
1. `memory_strategy.cr:230` — change to `if taints.cyclic?` (remove `|| taints.ffi_exposed?`)
2. `memory_strategy.cr:274` — same change for aggressive mode
3. Verify: `@[Transfer]` on an FFI method should cause Crystal to skip rc_dec for
   the transferred args. This works naturally: Transfer marks args as ArgEscape,
   they get ARC, but the value is handed off — no rc_dec because the C side owns it.
   Confirm this path works end-to-end after rc_dec insertion (Task 2).

**Tests:** Compile a program with `lib LibC; fun strlen(s : UInt8*) : UInt64; end`
and verify the string argument gets ARC (not GC) strategy.

---

## Task 2: Insert rc_dec at Variable Reassignment

**File:** `src/compiler/mir/hir_to_mir.cr`

**Problem:** When a mutable local holding an ARC pointer is overwritten (e.g.,
`tree = make_tree(18)` in a loop), the old value never gets rc_dec.

**Where to insert:** Wherever a Store writes to a stack slot that holds an ARC pointer.

**Implementation:**

### 2a. Track ARC slots

Add a new instance variable to track which stack slots hold ARC-managed pointers:

```crystal
@arc_slots : Hash(ValueId, Bool) = {} of ValueId => Bool
# key = stack slot ValueId, value = true if atomic
```

Populate it in `lower_allocate` after `select_memory_strategy`:
- If strategy is `ARC` → `@arc_slots[ptr] = false`
- If strategy is `AtomicARC` → `@arc_slots[ptr] = true`

Also clear it per-function in `lower_function_body` (line ~811, where other
per-function maps are reinitialized).

### 2b. Insert rc_dec before Store to ARC slot

Find all places where `builder.store(slot, new_value)` writes to a known ARC slot.
Before the store, insert:

```crystal
if @arc_slots.has_key?(slot)
  old_value = builder.load(slot, @stack_slot_types[slot])
  builder.rc_dec(old_value, atomic: @arc_slots[slot])
end
builder.store(slot, new_value)
```

**Key locations to check:**
- `lower_allocate` (line ~1292) — stores constructor args to fields. These are
  FIELD stores on the newly allocated object, not slot reassignment. Skip these.
- `lower_copy` (line ~3821) — reads FROM slots (load). Not a store. Skip.
- Phi resolution — may store into slots. Check `resolve_pending_phis`.
- Any explicit `builder.store()` where target is a stack slot from `@stack_slot_types`.

**Important edge case:** The FIRST store to an ARC slot (right after allocation)
should NOT rc_dec because there's no old value. Options:
- Initialize ARC slots with null pointer at allocation time
- Track "first store" flag per slot
- Simplest: always init ARC slots to null. rc_dec(null) should be a no-op.
  Verify `__crystal_v2_rc_dec` handles null (llvm_backend.cr:2648).

### 2c. Verify rc_dec(null) is safe

Check `__crystal_v2_rc_dec` in llvm_backend.cr:2648. If it doesn't guard against
null, add a null check:
```llvm
define void @__crystal_v2_rc_dec(ptr %ptr, ptr %destructor) {
  %is_null = icmp eq ptr %ptr, null
  br i1 %is_null, label %done, label %dec
dec:
  ; ... existing decrement logic ...
done:
  ret void
}
```

---

## Task 3: Insert rc_dec at Function Return

**File:** `src/compiler/mir/hir_to_mir.cr`

**Problem:** `lower_terminator` for `HIR::Return` (line ~4447) does `builder.ret(value)`
without cleaning up local ARC variables.

**Implementation:**

In `lower_terminator`, before `builder.ret(value)` or `builder.ret()`:

```crystal
when HIR::Return
  # Cleanup: rc_dec all local ARC values (except return value)
  return_value_slot = term.value ? get_value(term.value) : nil
  @arc_slots.each do |slot, atomic|
    next if slot == return_value_slot  # caller takes ownership of return value
    current = builder.load(slot, @stack_slot_types[slot])
    builder.rc_dec(current, atomic: atomic)
  end
  # Then emit the actual return
  if v = term.value
    # ... existing return logic ...
```

**Edge case — return value:** The returned value should NOT be rc_dec'd here.
The caller is responsible. The rc_inc at allocation already accounts for this
(refcount = 1 = the caller's reference).

**Edge case — early returns:** If a function has multiple return points (e.g.,
`if ... return x ... end ... return y`), each return terminator needs its own
cleanup. Since cleanup is inserted per-terminator, this is handled naturally.

**Edge case — Unreachable terminators:** `HIR::Unreachable` does not need cleanup
(program is aborting). Skip.

---

## Task 4: Insert rc_dec at Scope/Loop Exit

**File:** `src/compiler/mir/hir_to_mir.cr`

**Problem:** In a `while` loop, variables declared inside the loop body should get
rc_dec at the end of each iteration, not just at function return.

**This is the hardest task.** Two approaches:

### Approach A: Scope-aware cleanup (precise)

Use `HIR::Local.scope` (ScopeId) to track which ARC slots belong to which scope.
When a terminator exits a scope (jump/branch to a block in a parent scope),
insert rc_dec for all ARC slots in the exiting scope.

Requires: mapping from scope → set of ARC slots. The scope tree is available
via `HIR::Function.scopes`.

### Approach B: Phi-based cleanup (simpler)

In a loop, the loop header has a Phi node for the loop variable. At the back-edge
(end of loop body jumping back to header), the OLD value from the previous iteration
is dead. Insert rc_dec for the old phi value before the back-edge jump.

This is simpler but only handles loops, not general scope exit.

### Recommended: Start with Approach A

It's more general and the scope information is already available. Steps:

1. Build `@scope_arc_slots : Hash(ScopeId, Array(ValueId))` — which ARC slots
   belong to which scope.
2. In `lower_local`, when allocating a mutable local, if the local's type will
   get ARC strategy, record it in `@scope_arc_slots[local.scope]`.
3. In `lower_terminator` for `Jump` and `Branch`, check if the target block's
   scope is a parent of the current block's scope. If yes, rc_dec all ARC slots
   from the scopes being exited.

**Complexity note:** This needs access to the scope of each HIR block. The
`HIR::Block` has a `scope` field. Map it during `lower_function_body` when
iterating blocks.

---

## Task 5: Verification

### 5a. Binary tree benchmark

```
cd ~/Projects/Crystal/crystal_v2_repo/examples
../bin/crystal_v2 bench_tree_crystal.cr -o bench_tree_crystal --release
```

After rc_dec is implemented:
- The program should produce the same result (correctness)
- Memory usage should be bounded (not growing linearly with iterations)
- Compare: `bench_tree_crystal` vs `/tmp/bench_tree` (C with free)

### 5b. LLVM IR check

```
DEBUG_LLVM_IR=1 ../bin/crystal_v2 bench_tree_crystal.cr -o bench_tree_crystal --release
grep -c "rc_dec" /tmp/crystal_v2_*.ll
```

Should show non-zero rc_dec count. Previously: 6211 rc_inc, 0 rc_dec.
After fix: rc_dec count should be comparable to rc_inc count.

### 5c. Regression tests

Run existing 68 tests. None should break — rc_dec is additive.

### 5d. fib(42) benchmark

Should be unaffected (no ARC objects in fib). Verify no performance regression.

### 5e. Memory leak check (optional)

If available, run bench_tree under leaks/valgrind to confirm no leaked TreeNode objects.

---

## Task 6: Deferred Batch Reclamation (LTP Spike/Ladder)

**Problem:** Per-block rc_dec works but adds overhead in hot loops — each rc_dec is
a memory write that may touch a cold cache line (the refcount at ptr-8).

**Idea:** Instead of immediate rc_dec, collect pointers into a thread-local buffer
and batch-process them periodically. This is cache-friendly and amortizes the cost.

**Design:**

### 6a. Thread-local release buffer

```crystal
# Runtime (LLVM IR): per-thread circular buffer of pending rc_dec pointers
@__crystal_v2_release_buffer : [1024 x ptr]  # fixed-size ring buffer
@__crystal_v2_release_count : i32             # current fill level
```

### 6b. Deferred rc_dec call

Replace `__crystal_v2_rc_dec(ptr, dtor)` at block end with:
```
__crystal_v2_release_defer(ptr)  ; append to buffer, O(1)
```

When the buffer is full (or at function return / scope exit), flush:
```
__crystal_v2_release_flush()     ; batch rc_dec all buffered pointers
```

### 6c. Flush triggers

- **Buffer full** (1024 entries) — flush immediately
- **Function return** — flush before ret (ensures deterministic cleanup)
- **Allocation pressure** — flush when malloc fails or threshold hit
- **Explicit** — `GC.collect` equivalent triggers flush

### 6d. Benefits

- **Cache-friendly:** batch rc_dec touches refcount headers sequentially
- **Amortized overhead:** one branch per defer vs full rc_dec path
- **Spike absorption:** short-lived temporaries in tight loops get batched
- **Ladder pattern:** long-lived objects skip the buffer (rc stays > 1)

### 6e. Risks

- **Delayed destructors:** files/sockets/locks won't close immediately
  - Mitigation: `@[Eager]` annotation forces immediate rc_dec for RAII types
- **Increased peak RSS:** objects freed in batches, not immediately
  - Mitigation: small buffer (1024) limits maximum delay
- **Complexity:** buffer management, flush at all exit points

### 6f. Implementation order

1. Add `__crystal_v2_release_defer` and `__crystal_v2_release_flush` to runtime
2. Replace per-block `rc_dec` with `release_defer` for non-RAII types
3. Emit `release_flush` at function returns
4. Benchmark: compare immediate vs deferred on bench_tree_crystal
5. Tune buffer size based on cache line / L1 size

**Prerequisite:** Tasks 1-5 complete (immediate rc_dec working correctly first).

---

## Execution Order

```
Task 1 (FFIExposed fix)    — DONE (commit cfbb59d4)
Task 2 (reassignment)      — SUPERSEDED by per-block cleanup (commit 4bb794c8)
Task 3 (function return)   — uses @arc_slots from Task 2
Task 4 (scope/loop exit)   — PARTIALLY DONE: per-block cleanup handles block-local temps
Task 5 (verification)      — DONE: 67/68 pass, tree benchmark bounded memory
Task 6 (deferred batch)    — optimization: batch rc_dec for cache efficiency
```

## Key Files

| File | What to change |
|------|---------------|
| `src/compiler/hir/memory_strategy.cr:230,274` | Remove `ffi_exposed?` from GC guard |
| `src/compiler/mir/hir_to_mir.cr:~811` | Add `@arc_slots` init |
| `src/compiler/mir/hir_to_mir.cr:~1299` | Populate `@arc_slots` after rc_inc |
| `src/compiler/mir/hir_to_mir.cr:~4447` | rc_dec at Return terminator |
| `src/compiler/mir/hir_to_mir.cr:~975` | Scope exit cleanup in lower_block/terminator |
| `src/compiler/mir/llvm_backend.cr:~2648` | Ensure rc_dec(null) is safe |

## Existing Infrastructure (DO NOT modify)

| Component | Location | Status |
|-----------|----------|--------|
| `MIR::RCDecrement` class | mir.cr:558 | Ready |
| `builder.rc_dec()` method | mir.cr:2045 | Ready |
| `emit_rc_dec()` LLVM emitter | llvm_backend.cr:10433 | Ready |
| `__crystal_v2_rc_dec` runtime | llvm_backend.cr:2648 | Ready (check null safety) |
| `RCElisionPass` optimizer | optimizations.cr:51 | Ready (removes matched pairs) |
| `EscapeAnalyzer` | escape_analysis.cr | Ready |
| `TaintAnalyzer` | taint_analysis.cr | Ready |
| `MemoryStrategyAssigner` | memory_strategy.cr | Ready (after Task 1 fix) |
| `@[Transfer]` annotation | ast_to_hir.cr:3459 | Ready |
| `MethodEffectSummary` | hir.cr:2088 | Ready |
