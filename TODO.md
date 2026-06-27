# Crystal V2 Bootstrap TODO

Updated: 2026-06-27
Branch: `work/s3-range-slice-frontier`

This is the active working backlog only. Historical detail is in git history,
especially `65eb6f62^:TODO.md`. Reusable evidence lives in `LANDMARKS.md`.

## 2026-06-27 — architecture stop-rule checkpoint: do not merge current branch yet

- CURRENT STATUS: branch `work/s3-range-slice-frontier` is still not
  merge-ready, but the previous broad dirty batch has been cut down. Stale
  `ADAMAS_*_LEDGER` probes, an unbacked `lower_field_get` Void guard, stale
  backend bootstrap rewrites, and a misleading `stage2_try_inline...` repro were
  removed instead of being carried forward. A fresh stage1 build produces a
  fresh s2, and the escaped-interpolation parser regression now passes under
  both stage1 and that generated s2:
  `regression_tests/stage2_escaped_interpolation_string_parser_repro.sh
  /tmp/adamas_cleaned_batch` and the same script with
  `/tmp/adamas_cleaned_batch_s2`. However, generated s2 compiling minimal
  full-prelude `puts "x"` still exits 139 during compilation after
  `pass3 after lower_main call`; fresh lldb stops in
  `Adamas::MIR::HIRToMIRLowering#lower_field_get(HIR::FieldGet)`. Treat this
  as the current red evidence; do not claim s2/s3 green.
- HARD BOUNDARY: keep `BlockOwner`. Do not revert `@block_owner` back to
  `NamedTuple` or positional `Tuple`; that rollback re-enters an already
  observed materialization/key-shape trap.
- FIXED: `case x; when StructConstant` now uses Crystal's
  `condition === subject` semantics for non-primitive conditions instead of raw
  storage/pointer equality. The focused guard is
  `regression_tests/struct_constant_case_equality_repro.sh`; it is red on
  baseline `d623f52f` (`case=miss`) and green on the fixed compiler
  (`case=hit`). Primitive scalar case comparisons still use raw `Eq`.
- FRONTEND SLICE CLOSED: s2 previously parsed `String#dump_or_inspect_unquoted`
  incorrectly because the two-pass `lex_string` fast path treated escaped
  `\\\#{` as real interpolation and swallowed the rest of the class body.
  `lex_string` now uses one processed scanner for all string literals, and
  processed token slices are retained through `StringPool`. The existing
  parsed-class debug oracle is also stage2-safe in body-count mode. The new
  regression is intentionally parser/HIR-frontier scoped; it does not claim
  full s2 program compilation.
- STALE EVIDENCE: the previous `IO#<<$String` / `String`-as-`Unknown` /
  `TypeRef.new(15)` case-identity ledger described an earlier frontier before
  the escaped-interpolation parser fix. Do not continue from that row unless it
  is re-observed on the current tree.
- REQUIRED NEXT SLICE (read-only/default-off first): localize the current
  `lower_field_get` crash. Record the exact HIR `FieldGet`, its owning
  function, object type, field name, field offset, field type, class-info field
  vector, and stage1-vs-s2 divergence. Do not add a consumer guard in
  `lower_field_get` unless the producer proves that the FieldGet is legitimate
  but the consumer mishandles it.
- DEAD-CODE/BLOAT TRACK: classify backend fallback and repair paths touched by
  the current batch (`emit_dead_code_stub`, `lookup_module_function_for_extern`,
  `fixup_call_arg_types`, `emit_functions_parallel` bootstrap workarounds) using
  `CodePathStatus` before deleting or expanding them. Backend fixes that
  re-resolve source-level semantics are not architecture fixes unless a
  materialization boundary says they are the owner.
- MERGE RULE: merge to `main` only after the current batch is split into
  verified commits or replaced by smaller verified slices, and after fresh
  stage1, fresh s2, direct `puts "x"`, the escaped-interpolation regression,
  and the relevant stage2 regressions all pass under the declared compiler.

## 2026-06-27 — fixed block-shorthand Array index dispatch

- FIXED: `parsed.map(&.[0])` and `parsed.map(&.[i])` no longer lower the
  synthetic `__arg0.[](idx)` CallNode to `Array(T)#[](Range)` while passing an
  `Int32` index as the Range pointer. The bug surfaced in s3 while compiling
  `src/adamas.cr`: `AstToHir#try_unify_tuple_variant_names` used
  `parsed.map(&.[i]).uniq`, and the generated s2 called
  `Array(String)#[](Range)` with an integer index, crashing in `Range#begin`.
- Root: parser block shorthand expands `&.[idx]` into a CallNode, not an
  IndexNode. The existing IndexNode path already treated `Array#[](non-Range)`
  as direct element access, but the CallNode path went through overload
  resolution and selected the Range overload despite `arg_types=Int32`.
  Fix: in `lower_call`, for `Array`/`StaticArray` receivers, `[]`, one arg, and
  an argument that is not Range by AST or TypeRef, emit the same `IndexGet`
  element access as IndexNode lowering.
- Regression guard: `regression_tests/block_shorthand_array_index_repro.sh`
  covers literal shorthand, local-index shorthand, explicit block indexing, and
  direct Range slicing.
- Verified for this slice:
  `regression_tests/block_shorthand_array_index_repro.sh
  /tmp/adamas_array_shorthand_fix`;
  `regression_tests/stage2_indexable_range_materialization_repro.sh
  /tmp/adamas_array_shorthand_fix`;
  `regression_tests/arc_unionwrap_cross_block_owned_return_repro.sh
  /tmp/adamas_array_shorthand_fix`; and
  `regression_tests/run_all_suites.sh /tmp/adamas_array_shorthand_fix 4`
  passed originals 151/151 + combined 36/36.
- Bootstrap status: fixed stage1 builds s2 successfully:
  `scripts/run_safe.sh /tmp/adamas_array_shorthand_fix 900 12288
  src/adamas.cr -o /tmp/adamas_array_shorthand_s2` exits 0. Fresh s2 then gets
  past the previous `Range#begin`/`try_unify_tuple_variant_names` crash, but s3
  still fails with a separate `Bus error` in `Slice(UInt8).cmp` called from
  `Slice(Tuple(String, Int32)).merge_sort!` /
  `Array(Tuple(String, Int32))#sort!` inside
  `AstToHir#resolve_union_method_call`. Treat that as the next frontier; do not
  conflate it with Array Range slicing.

## 2026-06-27 — fixed sort comparator Proc carrier through s2

- FIXED: the post-Array-shorthand s2 no longer crashes in the
  `Array(Tuple(String, Int32))#sort!` / `Slice(UInt8).cmp(..., Proc)` corridor
  while compiling `src/adamas.cr` toward s3. The old crash was a double-carrier
  Proc bug: `Array#sort!(&block)` forwarded a materialized Proc object into
  `Slice#sort!(&block)`, which wrapped it again; `Slice(UInt8).cmp` then loaded
  the inner Proc object pointer as if it were a function pointer.
- Root slice: block-suffix calls now forward the raw callback carrier to callee
  block parameters. Raw callback materialization remains reserved for ordinary
  `Proc` / `Proc?` parameters, and the raw-proc coercion path now skips callee
  parameters that are real block parameters.
- Second boundary in the same corridor: once the carrier was correct,
  `Slice(UInt8).cmp(v1, v2, block)` still lowered `block.call(v1, v2)` as
  `void` because the comparator parameter is bare `Proc` and loses return
  shape. This slice recovers the stdlib comparator contract for
  `Slice(UInt8).cmp` as `Int32`; this is not a general erased-Proc return
  inference fix.
- Regression guard: `regression_tests/sort_by_tuple_key_runtime_repro.sh` now
  fails on crash/non-zero exit or wrong output and requires the sorted output
  `1,2,3`.
- Verified for this slice: `regression_tests/sort_by_tuple_key_runtime_repro.sh
  /tmp/adamas_block_proc_cmp_fix` passes; block-shorthand Array index,
  stage2 indexable Range materialization, and ARC UnionWrap cross-block guards
  pass; `regression_tests/run_all_suites.sh /tmp/adamas_block_proc_cmp_fix 4`
  passes originals 151/151 + combined 36/36; static LLVM IR shows
  `Array#sort!$block` forwarding raw `%block` to `Slice#sort!$block`,
  `Slice#sort!$block` materializing exactly one Proc for `merge_sort!`, and
  `Slice(UInt8).cmp(..., Proc)` calling the comparator as `i32` and returning
  that `i32`.
- Bootstrap status: fixed stage1 builds s2 successfully:
  `scripts/run_safe.sh /tmp/adamas_block_proc_cmp_fix 900 12288 src/adamas.cr
  -o /tmp/adamas_block_proc_s2` exits 0. Fresh s2 gets past the previous
  sort/comparator crash, then s2->s3 fails later with `SIGSEGV` in
  `AstToHir#inline_try_with_block` after `pass3 after lower_main call`.
  Disabling try inline changes the failure to
  `STUB CALLED: Adamas::HIR::AstToHir::class_name:String#empty?`, so the new
  frontier is not yet root-classified; do not conflate it with the closed
  sort/Proc carrier slice.

## 2026-06-27 — fixed enum-member generic inference for filled arrays

- FIXED: generated `s2b` no longer crashes the no-prelude smoke in
  `Adamas::HIR::EscapeAnalyzer#build_summary` after `lower_main`. The first bad
  producer was `EscapeSummary#initialize`: `Array.new(param_count,
  LifetimeTag::StackLocal)` inferred the generic owner as
  `Array(LifetimeTag::StackLocal)` instead of `Array(LifetimeTag)`. That
  singleton-member array materialized `initialize(Int32, LifetimeTag)` as a
  no-arg zeroing body, leaving `@buffer = null`; `build_summary` then wrote the
  first parameter lifetime into that null buffer.
- Root: `infer_type_name_from_node(PathNode)` treated enum member paths as type
  names when generic constructors inferred type arguments from AST nodes. Enum
  members are values of their declaring enum, so `SomeEnum::Member` now
  canonicalizes to `SomeEnum` when the path matches a registered enum member.
- Regression guard: `regression_tests/enum_member_array_new_repro.sh` covers
  `Array.new(size, Enum::Member)` and verifies the array is usable as
  `Array(Enum)`.
- Verified for this slice: `crystal build src/adamas.cr -o bin/adamas
  --error-trace`; `regression_tests/enum_member_array_new_repro.sh
  bin/adamas`; `regression_tests/array_filled_pointer_value_dup_repro.sh
  bin/adamas`; `regression_tests/hash_block_shape_default_proc_repro.sh
  bin/adamas`; `regression_tests/run_all_suites.sh bin/adamas 4` passed
  originals 151/151 + combined 36/36. ASAN bootstrap
  `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_enum_owner_fix --timeout 900 --mem 12288` builds s2 and
  both s2 plain and no-prelude smokes pass. Static IR check shows
  `EscapeSummary#initialize` now calls
  `Array(Adamas::HIR::LifetimeTag).new(Int32, LifetimeTag)`, whose initializer
  allocates/fills the buffer for non-zero size.
- CURRENT FRONTIER: one stage deeper, ASAN
  `scripts/bootstrap_chain.sh --stages 3 --out
  /tmp/adamas_bootstrap_enum_owner_fix_s3 --timeout 900 --mem 12288` gets
  through s1 and s2 (both smokes green), then fails the s3 build during module
  registration (`module register idx=151/268`) in
  `Adamas::Compiler::Frontend::ExprId#invalid?`. `ExprId` is a 4-byte struct,
  but generated `invalid?` has signature `(ptr %self)` and the crashing receiver
  is `0x000c00001102`, a non-null scalar-looking value. Treat this as the next
  by-value `ExprId`/struct-call ABI frontier; do not patch `invalid?` with a
  broader guard, because the immediate problem is an invalid call/receiver
  representation.

## 2026-06-22 — s2b phantom `Adamas::MIR::Hash` under-alloc: tactical fix landed; resolver bug A deferred

- FIXED (tactical, this branch): self-host `@value_def_block` backend crash
  (`emit_function` → `@value_def_block.clear` → `__bzero` @ `0x7fffffffffffffff`).
  Root: the debug reopens `class ::Hash(K,V)` / `struct ::Set(T)` /
  `class ::Array(T)` (adding `adamas_debug_structural_bytes`) were nested inside
  `module Adamas::MIR` in `llvm_backend.cr`; the absolute `::` is stripped at name
  extraction and the bare builtin base is re-qualified to a PHANTOM
  `Adamas::MIR::Hash` generic template (no ivars) → size-4 ClassInfo →
  `.new` under-allocates 12B while real `::Hash#initialize` writes ~56B →
  adjacent-heap stomp. Fix = moved the 3 reopens to top level (outside the
  module). Verified: 0 `Adamas::MIR::(Hash|Set|Array)` phantom symbols,
  `@value_def_block` now real `::Hash(UInt32,UInt64)` (64B, type_id 2045),
  `x=1` 5/5 EXIT 0, suites 148/148 + 36/36, `hash_dual_typeref_phantom_repro` PASS.
- DEFERRED — central resolver bug (A): an absolute `class ::X` reopen written
  *inside* a module must preserve the top-level base in definition registration.
  `definition_leaf_name_from_header_text` (ast_to_hir.cr:6686) drops the `::`;
  `qualified_nested_type_name` (:6977) and `resolve_class_name_for_definition`
  (:45225) then re-qualify the bare builtin base with the enclosing namespace.
  Needs a coordinated definition+reference fix; 5 narrow attempts failed (see
  memory `s2b_value_def_block_phantom_hash_underalloc`). NOT fixed here.
- NEW FRONTIER (surfaced by the fix, NOT a regression): s2b compiling a
  non-trivial program stack-overflows (SIGBUS) in the `Array(T)#join` super-chain
  recursion (`join → join_super_from_Enumerable → join_super_from_Indexable →
  join`), crashing in `String::Builder#initialize`. Separate super-chain family
  bug (cf. `super_chain_module_class_collision_fix`); do not bundle.

## Goal

Reach a clean bootstrap corridor:

`original -> stage1 -> s2b -> s3b -> s4b -> s5b`

with normalized HIR/MIR/LLVM semantic equivalence across stages.

Working policy:

- Prefer fast `--no-prelude` oracles.
- Use `s1 -> s2b` as the main integration gate.
- Run `s1 -> s5b` rarely, after `s1 -> s2b` is clean.

## 2026-06-26 — fixed s2b no-prelude interpolation helper materialization

- FIXED: fresh generated `s2b` no longer aborts the no-prelude interpolation
  smoke on `STUB CALLED:
  Adamas::MIR::LLVMIRGenerator#interpolation_i32_arg(String, UInt32, String,
  Int32, <large union>)`. The immediate boundary was the backend helper call
  sites: `part_type` is a compiler metadata value whose source contract is
  `Nil | MIR::TypeRef`, but V2 could record the callsite hint argument as a
  large value-domain union under self-hosting. Each call into
  `interpolation_i32_arg(..., hint_type : TypeRef?)` now asserts that boundary
  contract with `part_type.as(TypeRef?)`, so the requested helper symbol is
  materialized as `Nil | TypeRef` instead of as a live huge-union abort stub.
- Scope: this is a focused frontier fix, not a global cure for value-domain
  pollution around compiler metadata values. A local annotation on `part_type`
  was tested and did not change the self-hosted helper symbol; the residual
  root-family remains "why V2 admits value-domain unions for TypeRef metadata
  flow". Do not generalize this slice into a backend stub rescue.
- Regression guard: `regression_tests/p2_generated_stage2_no_prelude_interp.sh`
  now reports this exact `interpolation_i32_arg` stub separately when it
  regresses.
- Verified for this slice: `crystal build src/adamas.cr -o
  /tmp/adamas_interp_cast_out --error-trace`;
  `regression_tests/p2_generated_stage2_no_prelude_interp.sh
  /tmp/adamas_interp_cast_out`; `regression_tests/run_all_suites.sh
  /tmp/adamas_interp_cast_out 4` passed originals 151/151 + combined 36/36.
  Fresh `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_interp_cast_s2_current --timeout 900 --mem 12288`
  builds s2 and the s2 no-prelude smoke passes. Static IR check on
  `/tmp/adamas_bootstrap_interp_cast_s2_current/cv2_s2.ll` shows the real
  `interpolation_i32_arg(String, UInt32, String, Int32, Nil | TypeRef)` body
  and no old live huge-union stub.
- CURRENT FRONTIER: the same fresh bootstrap-chain run built s2 but its first
  full-prelude plain smoke hit a separate `EXIT 133` / `EXC_BREAKPOINT` in
  `libsystem_malloc`, with lldb showing
  `__adamas_file_read -> AstToHir#constant_source_text ->
  record_constant_definition` during module/class registration. A direct plain
  rerun can pass, but a repeated smoke reproduced the trap, so do not claim
  full `s1 -> s2b` green or attempt `s3b` until this full-prelude
  `constant_source_text`/file-read memory frontier is reduced.

## 2026-06-26 — fixed over-broad filled-array helper fast-path; next smoke frontier named

- FIXED: `Array.new(size, value)` no longer routes every non-Bool value through
  the Int32 filled-array helper. That helper hardcodes 4-byte element stride and
  the `Array(Int32)` runtime type id, so pointer-valued arrays such as
  `Array(String).new(2, "x")` received an 8-byte backing buffer for two pointer
  elements. A later `Array#dup` copied 16 bytes and ASAN reported a
  heap-buffer-overflow in `__adamas_ptr_copy`.
- Root: the HIR call fast-path in `ast_to_hir.cr` treated
  `Array.new(size, value)` as a generic filled-array constructor but selected
  only `__adamas_array_new_filled_bool` or `__adamas_array_new_filled_i32`.
  The helper contract was narrower than the call intercept. Fix: use the
  helpers only for their exact element types (`Bool`, `Int32`) and let all other
  element types use the normal `Array(T).new` materialization path.
- Regression guard: `regression_tests/array_filled_pointer_value_dup_repro.sh`
  compiles and runs `Array(String).new(2, "x").dup` under ASAN.
- Verified for this slice: `crystal build src/adamas.cr -o bin/adamas
  --error-trace`; `regression_tests/array_filled_pointer_value_dup_repro.sh
  bin/adamas`; focused `Array(Int32)`/`Array(Bool)`/`Array(String)` smoke;
  `regression_tests/run_all_suites.sh bin/adamas 4` passed originals 151/151 +
  combined 36/36.
- Bootstrap status: ASAN `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_plain_asan_arrayfix --timeout 900 --mem 12288` builds
  s2. The old `Array(HIR::TypeRef)#dup` heap-buffer-overflow is gone. Both s2
  plain and no-prelude smokes now stop at a new separate frontier:
  `Hash(Adamas::Compiler::Semantic::DefIdentity, Int32).new(Int32, Nil)`
  dereferences null (`READ` from zero page, exit 134). The prior
  `constant_source_text`/file-read frontier is therefore stale for this branch;
  do not keep debugging it without re-reproduction.
- CLOSED FOLLOW-UP (`bf67d667`): standalone `Hash(String, Int32).new(0)`,
  `Hash(String, Int32).new { ... }`, and `Hash(String, String).new("x")`
  default-provider reducers now compile and run. Root: generated allocator
  lookup could miss `Hash#initialize(block : Proc?, *, initial_capacity)` and
  raw block callbacks passed as Proc/Proc? arguments were not materialized as
  heap Proc objects. Fix: retry allocator initialize lookup with named-only
  compatibility after the positional miss, materialize raw callback values at
  Proc/Proc? call boundaries, and preserve raw callback carrier provenance for
  Proc-typed block-wrapper parameters. Regression guard:
  `regression_tests/hash_default_provider_proc_repro.sh`.
- Verified for this slice: `crystal build src/adamas.cr -o bin/adamas
  --error-trace`; `regression_tests/hash_default_provider_proc_repro.sh
  bin/adamas`; `regression_tests/array_filled_pointer_value_dup_repro.sh
  bin/adamas`; stateful closure Hash default-provider smoke; and
  `regression_tests/run_all_suites.sh bin/adamas 4` passed originals 151/151 +
  combined 36/36.
- CURRENT FRONTIER: ASAN
  `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_hash_default_fix --timeout 900 --mem 12288` now builds
  s2, but s2 plain/no-prelude smokes still fail in a sibling Hash constructor
  materialization case. In `cv2_s2.ll`,
  `Hash(Adamas::Compiler::Semantic::DefIdentity, Int32).new(Int32, Nil)` now
  correctly builds a heap Proc default provider, then calls
  `new$block$arity1` after loading `initial_capacity` from a null Nil pointer.
  The target `new$block$arity1` body was materialized with an `Int32`
  initial-capacity parameter and reused for the default-value path where
  `initial_capacity` is Nil. Treat this as an arity-only block-wrapper
  call-shape/materialization collision, not as the raw Proc/default-provider
  root fixed by `bf67d667`.

## 2026-06-26 — fixed tuple/hash bootstrap frontiers; next s2b frontier named

- FIXED: mixed tuple equality/hash and Hash tuple keys with nilable fields no
  longer miscompile under stage1 V2. Two root causes were removed:
  (1) mixed tuple element comparison/hash now lowers element-wise instead of
  routing scalar elements through String equality/hash shapes; (2) tuple
  container provenance is preserved through HIR -> MIR `IndexGet`, so Hash
  tuple keys are not read with Array `size/buffer` layout.
- FIXED: `Int32#remainder(Int64)` / `Crystal::Hasher.reduce_num(Int32)` no
  longer truncates the large Int64 modulus before `srem`; div/rem now evaluate
  in an operation width wide enough for both operands, then truncate to the MIR
  result width.
- Regression guards:
  `regression_tests/tuple_equality_hash_repro.sh`,
  `regression_tests/hash_tuple_key_nilable_field_repro.sh`,
  `regression_tests/int_remainder_mixed_width_repro.sh`, and
  `regression_tests/stage2_indexable_range_materialization_repro.sh`.
- Verified: `crystal build src/adamas.cr -o /tmp/adamas_commit_candidate
  --error-trace`; focused guards above; existing
  `hash_named_tuple_index_assign_materialization_repro.sh`;
  `regression_tests/run_all_suites.sh /tmp/adamas_commit_candidate 4` passed
  originals 151/151 + combined 36/36.
- PREVIOUS FRONTIER (closed by the section above): fresh
  `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_d48a73dc_s2 --timeout 900 --mem 12288` builds s2b and
  passes the plain smoke, but the generated s2b fails the no-prelude smoke with
  `STUB CALLED:
  Adamas::MIR::LLVMIRGenerator#interpolation_i32_arg(String, UInt32, String,
  Int32, <large union>)`. Do not attempt s3b until this
  `interpolation_i32_arg` materialization frontier is reduced.

## 2026-06-25 — fixed s2b full-prelude wildcard base-dir corruption

- FIXED: produced s2b no longer falls into `error: Unreachable` while resolving
  stdlib `indexable.cr`'s `require "./indexable/*"`. Root: `safe_dirname`
  still depended on `String#rindex('/')`; under self-hosting that call returned
  the final `.cr` byte position for `.../indexable.cr`, producing
  `.../src/stdlib/indexable.` as `base_dir`. The primary wildcard resolver then
  looked for `indexable./indexable`, returned nil, and the source fallback
  reached the stage2-broken `Dir.glob` path. Fix: split CLI paths with a
  byte-local reverse separator scan instead of `String#rindex(Char)`.
- Regression: `regression_tests/stage2_full_prelude_wildcard_require_repro.sh`
  is a focused s2b guard. It is red on the old s2b (`Warning: Could not resolve
  require './indexable/*'` / `error: Unreachable`) and green when
  `./indexable/*` resolves to `src/stdlib/indexable/mutable.cr`.
- NEW FRONTIER: the same full-prelude `puts 42` corridor now passes parsing and
  HIR setup, then aborts in `lower_main` with
  `STUB CALLED: Adamas::HIR::AstToHir#yield_return_function_for_block_call?...`.
  This is a separate materialization/demand frontier; do not bundle it with the
  path helper fix.

## 2026-06-26 — fixed s2b yield-return block-call nilable wrapper materialization

- FIXED: produced s2b no longer aborts in `lower_main` on
  `STUB CALLED: Adamas::HIR::AstToHir#yield_return_function_for_block_call?...`.
  Root: source registration only had the concrete first-argument overload
  (`mangled_name : String`), while the self-hosted call demand used
  `mangled_name : String?`. The materializer could not find a DefNode for the
  nilable wrapper and emitted an undefined-extern stub. Fix: add the explicit
  `String?` overload that fail-closes on nil and delegates to the concrete
  overload when present.
- Regression: `regression_tests/stage2_yield_return_block_call_materialization_repro.sh`
  is red on the post-dirname s2b and green once the nilable wrapper is
  materialized. It is intentionally focused: downstream full-prelude compilation
  may still fail after this frontier has moved.
- NEW FRONTIER: the same full-prelude `puts 42` corridor now reaches a later
  abort in `AstToHir#lower_block_to_proc(...)`. This is a separate
  block/proc materialization-demand frontier; do not bundle it with the
  yield-return wrapper fix.

## 2026-06-26 — fixed s2b lower_block_to_proc arena type materialization

- FIXED: produced s2b no longer aborts in `lower_main` on
  `STUB CALLED: Adamas::HIR::AstToHir#lower_block_to_proc...`. Root: the source
  helper signature requires `block_arena : Frontend::ArenaLike`, but self-hosted
  lowering inferred the local `block_arena_for_proc` at the three materialization
  callsites as wider unions such as `Nil | ArenaLike | String` or pointer-erased
  forms. Resolver saw the registered overload but rejected it as incompatible,
  then queued/stubbed the call-symbol. Fix: add explicit `ArenaLike` local
  annotations at the three `lower_block_to_proc` callsites. This preserves the
  runtime arena selection expression and only restores the declared helper
  contract for call-symbol materialization.
- Regression: `regression_tests/stage2_lower_block_to_proc_materialization_repro.sh`
  is red on the post-yield s2b (exact `lower_block_to_proc` stub) and green once
  the arena local is constrained. The guard is intentionally focused: it accepts
  the downstream full-prelude failure after the stub frontier moves.
- Verified: stage1 build; old-s2b red/new-s2b green focused guard; existing
  yield-return guard remains green; fresh s2b compiles and runs no-prelude
  `x = 1`; full stage1 suites pass 149/149 originals + 36/36 combined.
- NEW FRONTIER: full-prelude `puts 42` now passes `lower_main` and crashes later
  in MIR lowering: `HIRToMIRLowering#set_block_map` called from
  `mir_block_for` -> `resolve_pending_phis` -> `lower_function_body`. Treat this
  as a separate HIR->MIR block-map/phi frontier, not as a block/proc
  materialization bug.

## 2026-06-25 — fixed HIR RTA pruning of materialized target symbols

- FIXED: self-compiled compiler IR no longer emits the aborting
  `Hash(UInt64, NamedTuple(class_name:String?, method_name:String?, is_class:Bool))#[]=`
  undefined-extern stub. Root was not a backend-forwarder gap: `lower_function_if_needed`
  could materialize a body under the resolved target symbol while the call path
  still used a related requested symbol, and HIR RTA pruned the unreferenced
  target body before MIR. Fix: when materialization chooses the target symbol
  for a distinct requested name, mark that target as a materialization keepalive
  root in `HIR::Module.reachable_function_names`.
- Regression: `regression_tests/hash_named_tuple_index_assign_materialization_repro.sh`
  builds self-IR through `run_safe` and fails on any matching abort stub.
- Verified: stage1 build; focused Hash/NamedTuple self-IR regression; split
  materialization + `split(Char)` + short-circuit-narrowing guards; full suites
  149/149 originals + 36/36 combined. Fresh s2b builds and compiles a no-prelude
  `x = 1` smoke. The later `error: Unreachable` frontier is superseded by the
  path-helper fix above.

## Open Design Constraints

- Do not solve block/proc or generic-container demand bugs with fixed nesting
  depth caps. Real Crystal programs can contain deeply nested block, tuple,
  hash, array, proc, and iterator shapes. Guards may use focused negative
  patterns to catch known bad demand, but production fixes must preserve
  demanded deep shapes and remove only proven non-demand/root pollution.

## Deferred Designs

- **`@[Inline]` field-embedding annotation** — see
  `docs/inline_field_annotation_sdd.md`. Status DEFERRED after a hostile
  Quadrumvirate (2026-06-16): the idea is sound but mis-ordered. It must NOT
  precede (1) consolidation of the 3 layout oracles through `LayoutContract`
  and (2) the #4 repr-flip fix, because a per-field pointer-vs-inline override on
  un-consolidated oracles injects #4-class non-deterministic crashes. v1 scope
  = struct fields only (= opt-in, incremental step-4, Crystal-checkable);
  class-field embedding deferred behind an interior-ref leak check. Demand is
  narrow (~2-3% of compiler ivars; containers/primitives dominate and are out
  of scope) — measure access-frequency before investing.

- **"struct vs class on stack" / unified object model** — see
  `docs/class_on_stack_unified_model_review.md`. Status DEFERRED after a hostile
  Quadrumvirate (2026-06-16): discussion record, not a plan. "struct vs class =
  only copy semantics" is an oversimplification (identity/mutation/nil/dispatch
  derive from copy policy); "class on stack, LLVM SROA finishes it" is false —
  the `$Dnew` malloc is struct-gated (`hir_to_mir.cr:5800`/`:5854`), so a
  StackLocal class still mallocs; the unified model is premature while #4 is
  open and perf is unmeasured. Same blockers as `@[Inline]` (oracle
  consolidation + #4 fix) plus sound interprocedural escape + non-observable
  identity. NOT current work — current work is struct inlining (step-4).

## ABI-rework: layout-oracle consolidation

Goal: collapse the layout oracles onto the single `LayoutContract` so the #4
repr-flip family cannot live in their disagreements.

IMPORTANT refinement (2026-06-16): there are TWO distinct repr regimes, not one.
(a) **Field storage** — a struct as a class/struct FIELD: inline iff
`user_struct_inline?` = family OR `size > pointer_word`. (b) **Container element**
— a struct as Array/Slice ELEMENT: inline iff `inline_container_family?` ONLY; a
>8-byte plain user struct is still a POINTER element (inlining it corrupts
`Array(Parameter)`, llvm_backend.cr:2773). The two regimes share only the family
sub-predicate. So "route every oracle through one repr predicate" is WRONG — it
would inject divergence. Consolidate the shared piece (the family name-list) and
keep the two regimes distinct.

- **1c — MIR field-access readers (DONE, `66d6c015` 2026-06-16).** Routed
  `lower_field_get` (hir_to_mir.cr:2863) and `lower_field_store_to_ptr` (:3047)
  through `LayoutContract.user_struct_inline?`. Surfaced and fixed a latent
  pointer-word boundary divergence: HIR `user_struct_inline?` used `>= 8` while
  the MIR readers used `> 8`, so an exactly-8-byte struct value was INLINE per
  HIR but a POINTER CARRIER per MIR — masked only because both occupy one slot,
  but a step-4 repr-flip in waiting. Aligned the contract to `>` (matches the
  behavioural readers). Behaviour-neutral: LayoutProbe decision set byte-identical
  (565 decisions); guard `struct_pointer_word_boundary_repro.sh`; suite 159/159 +
  31/31. Per `[[abi_slot_conflict_metric_invalid]]` this is a correctness/clarity
  consolidation, NOT itself a #4 fix.
- **Demand (measured 2026-06-16).** step-4 target is a narrow tail: ~11 distinct
  small (<8B) value-struct field-slots (~5% of struct types); most struct fields
  are already ≥8B inline (215 distinct InlineBytes). Win concentrates in
  runtime-hot structs (Atomic, SpinLock, Timers, Arena::Index); access-frequency
  still unmeasured.
- **2a — LLVM container-element oracle (DONE, 2026-06-16).** Routed
  `inline_container_struct_type?` (llvm_backend.cr:2796) through
  `LayoutContract.inline_container_family?`, collapsing the duplicated family
  name-list (was also at layout_contract.cr:124) onto the single source.
  Behaviour-neutral (textually the same 3 prefixes under the same struct/size
  gate); via the container regime, NOT `user_struct_inline?`. Guard
  `struct_pointer_word_boundary_repro.sh`; suite 159/159 + 31/31.
- **1b — label unification (REFRAMED, not a neutral routing).** Routing the
  LayoutProbe container-element label through `LayoutContract.repr` is NOT
  behaviour-neutral: `repr` encodes FIELD semantics (`user_struct_inline?`,
  size>8 → InlineBytes) while the container-element probe uses CONTAINER
  semantics. Doing it as-is would make the label disagree with the actual
  storage. Needs a container-regime `repr` variant first, or leave the probe
  label site-local. LOW priority (diagnostic only).
- **mir_field_storage_size (REFRAMED, NOT a repr oracle).** hir_to_mir.cr:6383
  is a SIZE helper (returns bytes, returns `desc.size` for aggregates), used
  only in `trivial_struct_initializer_covers_all_storage?` where a wrong size is
  fail-safe (skips the trivial-init opt, no miscompile). It is NOT a #4 repr-flip
  source and should NOT be force-routed through the repr predicate (that would
  change small-struct field sizes 4→8 and toggle the opt). Leave as-is; document.
- **Next: step-4 flip.** With the field regime single-sourced (1c) and the
  container family list single-sourced (2a), the remaining work toward the perf
  win is the step-4 flip itself — make small (<8B) user-struct FIELDS inline at
  `user_struct_inline?` (the one flip point), gated/measured per the demand tail
  above. This is the Collapse move (remove the carrier box), CAUTION-tier; needs
  the #4 producer understood first.
  - **Scaffold shipped (gated OFF), `7abbfa08`.** `ADAMAS_INLINE_SMALL_STRUCTS`
    env gate read at COMPILE time via `LayoutContract.user_struct_inline?`;
    gate-OFF byte-identical to baseline (no rebuild needed to toggle).
  - **gate-ON full parity reached (2026-06-18).** Running the full matrix gate-ON
    vs the gate-OFF baseline surfaced exactly two non-routed readers, both fixed
    (each byte-neutral at the default gate-OFF):
    1. A struct-typed ivar whose default degrades to a scalar literal — e.g.
       `@__evloop_data : Arena::Index = INVALID_INDEX` collapsing to `literal 0`
       — crashed the inline-struct field store at startup (memcpy from a scalar
       register). Fix: `generate_allocator` (ast_to_hir.cr, both generators) now
       routes a struct ivar whose lowered default is NOT itself a struct value to
       a zero-struct `Allocate` (declared default still lost — separate documented
       gap). Guard `struct_ivar_module_default_inline_repro.sh`.
    2. A small (≤ pointer word) struct as a Tuple/NamedTuple element:
       `register_tuple_types` keeps it a pointer-word CARRIER, but
       `lower_field_get`/`lower_field_store_to_ptr` applied the step-4 FIELD flip
       → the carrier slot was misread as inline bytes (repr-flip). Fix: suppress
       only the step-4 small flip for a tuple receiver (`field_receiver_is_tuple?`
       in hir_to_mir.cr); large structs (> pointer word) inline in both regimes
       and are unchanged. Guard `tuple_small_struct_element_inline_repro.sh`
       (proven bad→good on pre/post-fix binaries).
    Result: gate-ON 131/131 + 36/36 + complex 17/19 == gate-OFF baseline (the 2
    complex fails are the pre-existing Array#find ёжики, present on both gates).
  - **Remaining: default-flip decision (owner call).** Flipping the shipped
    default to ON is CAUTION-tier (ABI change, also affects s3b). Gate it on a
    measured perf win over the runtime-hot small-struct tail
    (Atomic/SpinLock/Timers/Arena::Index) — measure first, then owner decision;
    then remove the env gate.

## Current Checkpoint

**2026-06-21 — gated fix: String#split nilable-limit monomorphization collision (Bug 2), gate `ADAMAS_BLOCK_SHAPE_SPECIALIZE` (`abi-struct-byvalue`).**
Per-shape block specialization: distinct `String#split$Char_Int32_Bool_block`(i32 limit) and
`Char_Nil_Bool_block`(ptr limit) instead of one collapsed `$Char$arity3_block`. Root of the
incomplete WIP was a 4th, emit-time block-target resolution site (`ast_to_hir.cr` ~78530) that
re-derived the arity name and overwrote the shape-keyed `mangled_method_name`; fixed by re-keying
its 3 branches through `shape_keyed_block_target` before `preserve_receiver_block_call_target`.
Gate DEFAULT OFF (fully inert; suites identical OFF/ON: originals 148/148, combined 36/36). Gated
reducer `string_split_int32_nil_limit_collision_repro.sh` (GATE=1 default) green: `int_limit=2
nil_limit=4`; IR has the two distinct defines, no `inttoptr 2->ptr`, no `load i32,ptr %limit`.
NOT default-on and NOT s2b-clean: gate-ON s2b now passes the Globber/String#split STARTUP crash
(gate-OFF still dies there) and reaches a SEPARATE deterministic backend crash —
`@value_def_block.clear` (Hash(UInt32,UInt64) @entries=-1) in `LLVMIRGenerator#emit_function`
during codegen. That is the next frontier (fresh session; localize crash frame + Hash state +
whether shape-block functions are the only HIR/MIR delta + minimal reducer). Bug 1 (single-Char
`split('/')` overload misdispatch, `string_split_default_nil_limit_repro`) remains separate/open.

**2026-06-20 — A′ BEHAVIOR: inline-value Array(C) storage ABI (gate `ADAMAS_INLINE_VALUE_ARRAY_STORAGE`) (`abi-struct-byvalue`).**
First slice where LLVM CONSUMES the A′ facts and changes the Array(C) ABI: a leaf-POD
value struct is stored INLINE in the Array buffer (stride C.size), read back as an
escape-safe heap-carrier copy, and the whole family (push/grow/realloc, [], delete_at/
shift/insert/concat, clear) uses the inline stride. Pure mechanical fact consumer:
emit_gep_dynamic reads `array_buffer_element_stride`; emit_store/load key off
`array_buffer_value`+`@inline_value_gep_value_slots`; emit_extern_call/emit_call rebuild
`logical_count*stride`; emit_array_get/set/new/literal read eligibility. Two sets
(strides vs value-slots) so pointer-arith geps never get heap-copy-load. 4 impl bugs
fixed: per-function ValueId set `.clear` (IO#gets_peek `switch i32` leak); array_new/
literal cap*8 under-alloc; **facts populated POST-MIR-opt** (the optimizer clones geps
and drops the durable props — cli.cr runs opt serially under the gate, populates, then
disables per-worker opt); clear-dest arith gep non-V3 element_type (broadened buffer-
gep marking). Surgical to_unsafe escape fix: exclude only COMPILER-SYNTHESIZED
dispatchers (`@synthetic_abstract_dispatchers`), so V3 is eligible but a user
`Box#to_unsafe{@a.to_unsafe}` stays caught. DoD: V3 genuinely flipped (ELIGIBLE,
stride-geps=19, 26 ivc_raw in Array(V3)#, delete_at ptr_move i32 12, behavior-identical
to legacy); wrapper-escape negative keeps WV ineligible; non-Array Pointer boxed;
gate-OFF byte-identical (broader suite 138/138 + 36/36, 0 fail); all 8 A′ reducers
green. v1 limit: positive target needs call-shaped Array usage (main-inlined-only
arr[i]/arr[i]= gives bv=0 → ineligible, fail-closed; v2 may add bv-from-ArrayGet/Set).
Reducers: inline_value_array_storage_behavior, inline_value_array_wrapper_escape_guard,
inline_value_nonarray_pointer_guard (re-pointable to behavior gate). NEXT: C (by-value
$Dnew/sret, stack-fast-path copy-on-load) and/or extend eligibility coverage.

**2026-06-20 — A′ facts extension: arith-gep stride + bulk logical_count (read-only) (`abi-struct-byvalue`).**
The behavior flip hit GPT's stop-signal (backend would have to re-derive provenance/
stride for the pointer-arith geps feeding `__adamas_ptr_move` — `getelementptr ptr`
stride-8 — and lacked a `logical_count` to rebuild byte counts). Partial behavior was
STASHED, facts extended instead (no backend oracle). New durable facts (gate
`ADAMAS_ARRAY_BULK_OP_FACTS`): `GetElementPtrDynamic#array_buffer_element_stride`
(set for EVERY @buffer-derived gep of an eligible C — value AND arith — via
`buffer_roots`); `ExternCall/Call#array_bulk_stride` + `#array_bulk_logical_count`
(ptr_move/copy count arg; memmove/memcpy/memset/malloc/realloc non-const Mul operand;
Pointer#clear/move_from count arg; no count → fail-closed Uncovered). All
eligibility-baked. Reducer: `Cov` ELIGIBLE with value+arith stride-geps + every
covered bulk op carrying logical_count (missing=0); strides only inside `Array(...)`
(outside=0); `Unc`/`Esc` get none; `Vec3#delete_at` arith geps now strided; gate-OFF
byte-identical; no `ivc_raw`. All 6 A′ reducers green. NEXT = resume the atomic
behavior flip (now a pure mechanical fact consumer), owner-gated, NOT started.

**2026-06-20 — A′ mini-AbiFacts: Array bulk-op coverage facts (read-only) (`abi-struct-byvalue`).**
Gate `ADAMAS_ARRAY_BULK_OP_FACTS`. The pre-behavior infra GPT/owner GO'd, built as a
durable typed-fact layer (aligns with the AbiFacts architecture note — minimal facts
for this slice, not a giant oracle). Typed facts in `mir.cr`: `ArrayBulkOpKind`,
`ArrayBulkCoverageReason`, `Type#inline_array_storage_eligible`,
`ExternCall#array_bulk_op`, `Call#array_bulk_op`. Pass in `hir_to_mir.cr` structurally
classifies every Array(C) @buffer bulk op (move/copy/clear/alloc/realloc) inside
monomorphic `Array(C)#` bodies via a precomputed `buffer_roots` set (strict, GPT-
constrained: @buffer-ivar Load; exact `Array(C)#to_unsafe`/`root_buffer` Call on an
Array(C) param; fresh strided malloc/realloc stored into self.@buffer). Eligibility =
`inline_value_safe(C) && no Heterogeneous/Uncovered op`. Reducer
`inline_array_storage_facts_probe.{cr,sh}`: `Cov` (push/[]/delete_at/shift/insert/
concat) → ELIGIBLE; `Unc` (adds dup/reverse → copy into fresh non-self buffer) →
ineligible `[…Uncovered]` (proves the refinement did NOT open a hole, fail-closed).
Read-only: gate-OFF IR byte-identical, no `ivc_raw`. NEXT = behavior commit per §3-§5
(now consumes both `array_buffer_value` + the bulk-op facts), owner-gated, NOT started.

**2026-06-20 — A′ behavior PREFLIGHT: design/DoD packet + non-Array guard (`abi-struct-byvalue`).**
`docs/inline_value_array_storage_behavior_plan.md` (PROPOSED, owner-gated) — the
design/DoD packet for the behavior slice that first makes LLVM read the A′ marks
(CAUTION/ABI). Incorporates GPT hardening: (1) ONE gate `ADAMAS_INLINE_VALUE_ARRAY_STORAGE`
that itself runs annotation (no two-env false-mark path); (2) Array-CONTEXT stride,
never a type-global `container_elem_storage_size_u64` flip (it is shared by
`Pointer(T)#bytesize`/StaticArray → would re-fire the refuted type-driven slice);
(3) atomic Array(C) family flip (alloc/realloc stride + store + copy-on-load +
memmove/delete_at/shift), not one GEP site; (4) copy-on-load v1 = heap carrier, no
stack fast path; (5) the reducer DoD + 48h pre-mortem. Preflight guard shipped:
`regression_tests/inline_value_nonarray_pointer_guard.{cr,sh}` — a leaf-POD struct
used only via `Pointer(Disc).value` (never in an Array) stays boxed: out=42, Disc
not-marked, array_buffer_value outside=0, 0 `ivc_raw` (the invariant the type-driven
slice violated). Packet revised per GPT review (4 blockers closed): memmove family
is MANDATORY not "if touched" (else first delete_at/shift = heap corruption);
buffer_ptr_arith uses an Array-context helper keyed on the monomorphic `Array(C)#`
body (not type-global) + fail-closed exclusion; the single behavior gate emits
`[IVANNOT]` so the guard's GATE re-point keeps mark evidence; copy-on-load reuses
the existing `[i64 INT64_MAX header][payload]` carrier (raw+8), not malloc(payload).
PREFLIGHT FINDING (measure-first, before any codegen): behavior is NOT one bounded
diff. The mutation family (delete_at/shift/insert/concat) memmoves via
`(@buffer+i).move_from` → `Pointer#bytesize(count)` = `count *
container_elem_storage_size_u64(T)` — type-global (llvm_backend.cr:13774/13807),
running inside shared `Pointer(T)#` bodies (NOT `Array(C)#`), so the durable
`array_buffer_value` mark (value Load/Store only) does not reach it. Inline stride
without mutation-family provenance = heap corruption on first delete_at/shift. This
fires GPT's stop-rule. NEXT = pre-authorized infra commit (§8): mutation-family
coverage marking (taint @buffer-derived Pointer(C) → mark memmove/arith sites,
read-only first, prove 0 outside Array) + executable fail-closed eligibility bit;
THEN the behavior flip. Behavior NOT started.

**2026-06-20 — A′ DURABLE annotation (infrastructure-only, NO behavior) (`abi-struct-byvalue`).**
Gate `ADAMAS_INLINE_VALUE_ANNOTATE`. Materializes the step-(c) safe-set IN MIR (not
STDERR): `populate_inline_value_safe_set` runs the SAME `{bv && !vd && !erased_flow}`
analysis (refactored into shared `compute_inline_value_safe_set(mark_provenance)`)
and persists two durable marks — `MIR::Type#inline_value_safe` (per-type eligible
flag) and `MIR::GetElementPtrDynamic#array_buffer_value` (per-site Array(C) @buffer
value-access provenance). `verify_inline_value_annotation` reads them back in a
separate pass. **NO lowering site reads either mark** ("same computation, durable
annotation, no behavior" — guards against silently re-deriving provenance by
type/name in LLVM = the refuted type-driven slice). Reducer
`regression_tests/inline_value_annotation_probe.sh` (reuses the step-(c) .cr):
Vec2 SAFE-MARKED, Vraw not-marked (value_derived → not eligible; doubles as the
behavior reducer's "unsafe types not eligible"), array_buffer_value marks inside
`Array(...)` bodies only (inside=10 outside=0), no `ivc_raw` in IR, gate ON vs OFF
IR byte-identical. NEXT (still owner-gated, NOT this step): behavior slice that
inline-stores ONLY at `array_buffer_value` sites whose elem is `inline_value_safe`.

**2026-06-20 — Step (c): read-only per-type inline-value SAFE-SET shipped (`abi-struct-byvalue`).**
`run_inline_value_safe_set_probe` (gate `ADAMAS_INLINE_VALUE_SAFE_SET_PROBE`).
v1 SAFE-SET = `{ C | bv && !vd && !erased_flow }`. The erased gate is FLOW-based
(does `Array(C)` / an upcast `Indexable/Enumerable(C)` actually flow into a
type-erased body) — it REPLACES the over-coarse variant signal (C ∈ the
program-wide `Indexable(T)#fetch` mega-union), which would WRONGLY exclude 3 types
incl. `Vec2`. KEY FINDING: this compiler monomorphizes ALL candidate-array access,
so `erased_flow` stays 0 — the durable reducer exercises `Vec2` via
push/each/[]/map AND the erasure-attempt forms (`Indexable(Vec2)` param, `.as` cast,
two-implementer abstract dispatch) and `Vec2` still classifies SAFE; the step-3 (c)
erased repr-mismatch hazard does NOT occur for candidate types; `erased_flow` is a
sound but dormant guard. Reducer `regression_tests/inline_value_safe_set_probe.{cr,sh}`:
one compile asserts `Vec2` SAFE (bv=1 vd=0 erased_flow=0, even under abstract
dispatch) + `Vraw` UNSAFE (value_derived access — raw `Pointer(Vraw)` read+write)
+ flow-based erased=0 + mega-union over-count + gate-neutral (IR diff=0). Read-only;
no codegen consumes the label. STEP-3 conditions: (a) DONE; (b) held; (c) DONE;
(d) negative reducer keeps 0 `ivc_raw`.
**Behavior slice (step 3) is owner-gated — NOT green-lit.**

**2026-06-20 — Step (a): leaf-storage-POD gate narrowed (`abi-struct-byvalue`).**
`leaf_storage_pod_struct?` no longer admits `k.pointer?` — a struct with a raw
pointer field (Pointer::Appender, Crystal::PointerLinkedList) is NOT
value-copy-safe (inline copy duplicates a live interior pointer), so it now
classifies as `ExistingLowering`. Classifier-only / read-only: no codegen
consumes the label on this base (`llvm_backend.cr` has no `ivc_raw`), gate ON vs
OFF IR byte-identical (normalized diff = 0). Reducer
`regression_tests/leaf_pod_struct_pointer_field_repro.{cr,sh}`: Vec2/Vec3 stay
InlineValueCopy, WithPtr (raw Pointer(Int32) field) → ExistingLowering. NEXT =
step (c) erased reconciliation / per-type safe-set (read-only first): the set of
types with a `buffer_value` store/read AND no erased/`value_derived` read path,
or explicit reconciliation for erased `Indexable(T)#fetch`. Behavior-slice only
after (c); invariant (b) held HARD — no global type-driven `Pointer(T)#<<`.

**2026-06-20 — A′ provenance marker: read-only proof shipped (`abi-struct-byvalue`).**
Step 2 of the A′ plan. `run_array_buffer_provenance_probe` (gate
`ADAMAS_ARRAY_BUFFER_PROVENANCE_PROBE`, default OFF, STDERR-only). Refines the
census "function-context" idea into a precise **buffer-base provenance** rule that
does NOT use the function name: a candidate `GetElementPtrDynamic` G (elem C, an
InlineValueCopy candidate) is in the A′ mark set (`buffer_value`) iff (1) `G.base`
= `Load(static GEP @buffer of a receiver typed `Array(C)`)` AND (2) G is the
address of a `Load`/`Store` of C. Four categories split the mark set from
look-alikes: `buffer_value` (mark) / `buffer_ptr_arith` (root_buffer / memmove
ptr arithmetic) / `value_derived` (raw `Pointer(C)[i]`, no @buffer chain) /
`neither` (resize realloc-ptr). **PROVEN:** on a probe mixing Array(Vec2) inline
access + a deliberate raw `Pointer(Vec2)[idx]` access, `buffer_value` lands ONLY
in `Array(C)#` bodies — **0 marks outside an Array body** — and the raw Pointer
access is `value_derived`, NOT marked. The `IO#gets_peek` `Pointer(C)#value`
blocker that sank the refuted type-driven slice is structurally excluded. Gate
ON vs OFF LLVM IR byte-identical (normalized diff = 0). Regression:
`regression_tests/array_buffer_provenance_marker_probe.{cr,sh}` (asserts the 0-
outside invariant + positive Array(Vec2) marks + negative Pointer(Vec2) not
marked + gate neutrality). Doc section: `docs/container_access_path_census.md`
"A′ provenance marker — read-only proof". STILL OPEN before step-3 behavior:
the 4 hard conditions below (leaf-gate narrowing; no global type-driven
`Pointer(T)#<<`; erased `Indexable(T)#fetch`/`Enumerable(T)` reconciliation OR
per-type safe-set — note an erased generic body's buffer GEP is `value_derived`
(self typed `Indexable(T)`, not `Array(C)`) so it would read inline-stored bytes
via the pointer-slot path unless reconciled; negative reducer stays 0 ivc_raw).
Step-3 order (owner+GPT, NOT a green light yet — behavior must CONSUME exactly
this provenance mark, not re-guess in LLVM by type/name): **(a) FIRST narrow the
leaf gate** — `leaf_storage_pod_struct?` still admits `k.pointer?`; raw-pointer-
field structs must go to `ExistingLowering`, with a reducer (Vec2/Vec3 →
InlineValueCopy, struct-with-raw-pointer-field → NOT InlineValueCopy). **(c) THEN
erased reconciliation / per-type safe-set** (else inline-store in `Array(C)#push`
+ pointer-slot read via erased `Indexable(T)#fetch` = repr mismatch).

**2026-06-20 — Container access-path census shipped (`abi-struct-byvalue`).**
Read-only diagnostic `run_container_access_census` (gate
`ADAMAS_CONTAINER_ACCESS_CENSUS`, default OFF; gate-OFF IR byte-identical after
normalizing non-det `@.stub_name_<hash>`). Buckets every InlineValueCopy-candidate
access by read|store × mechanism × provenance (recoverable / concrete_np / erased).
Full table: `docs/container_access_path_census.md`. Decisive finding: the real
Array element store/load is a raw `GetElementPtrDynamic`+Store/Load INSIDE the
monomorphic `Array(Concrete)#push`/`#unsafe_fetch` body (symmetric), NOT
ArrayGet/ArraySet and NOT the type-erased `Indexable#fetch` path (erased = 3.4%
reads, 0 for Vec2/Vec3 → the erased-read falsifier did NOT fire). 35 candidates
(Vec2/Vec3 + 33 stdlib value structs). **Decision (owner+GPT): A′ now, C later.**
A′ next slice = a **read-only provenance marker FIRST** (function-context +
buffer-base provenance: mark a raw GEP only if it addresses Array.@buffer, not any
`Pointer(T)` inside an `Array(...)#` body; prove 0 marks outside Array buffers),
THEN behavior (store/load by marker, heap-copy carrier on load). Hard conditions
before behavior: (a) restore leaf-gate narrowing — raw-pointer-field structs
(PointerLinkedList/Pointer::Appender) are NOT leaf-storage-POD; (b) no global
type-driven `Pointer(T)#<<`; (c) close erased reconciliation OR ship v1 per-type
safe-set (only types with no erased access in the lowered module); (d) reducer
must include a NEGATIVE (IO#gets_peek / `Pointer(Range/Hasher)#value` → 0 ivc_raw).

**2026-06-19 — ABI-rework + s2b GC fix MERGED to `main` and pushed.** Two
revertable merge commits on `main` (now `71b707ff`, == `origin/main`):
`d07b07d6` merges `abi-step4-inline-struct` (full ABI-rework series: LayoutContract
consolidation 1a/1c, gated-OFF step-4 small-struct inline flip
`ADAMAS_INLINE_SMALL_STRUCTS`, StaticArray by-value memcopy, SplatNode guard,
docs — all default-behavior-neutral), and `71b707ff` merges
`s2b-twoheap-gc-fix-D` (brought only `e635fbc4`, the GC two-heap redirect).
Post-merge verification: `bin/adamas` builds clean; suites **originals 131/131 +
combined 36/36, 0 fail** (count rebalanced vs old 158/31 by main's test-batching
commits); `gc_aware_realloc_gating_repro` PASS; all 4 new struct/ABI repros
(splat / struct_ivar_module_default / struct_pointer_word_boundary /
tuple_small_struct_element) PASS. No regressions from the merge.

**2026-06-19 — By-value struct ABI: Stage 0 census shipped (`abi-struct-byvalue`,
`19e72d7d`).** Read-only diagnostic (gate `ADAMAS_STRUCT_BYVALUE_CENSUS`, default
OFF): for every user-struct ctor call, classify result flow (field_store /
container / arg / return / local / mixed) + POD vs ref. Decision-grade finding:
the common `Particle.new(Vec2.new(...))` lands in `arg`, NOT `field_store`, so no
single bucket is "the flip set" — exact eligibility is for a later escape/inline
predicate. GPT round-2 hostile review confirmed (anchors re-verified vs live
code): (1) `arg` too coarse — needs sub-census; (2) inline-proof must exactly
match `lower_field_store_to_ptr`/`use_memcopy` incl. `suppress_step4_tuple`
(else stack-alloc + pointer-carrier store = UAF); (3) `type_needs_rc?` doesn't
recurse through struct fields + `struct_type_is_pod?` optimistic default → unfit
as flip gate; (4) shared escape walker trusts receiver-self as borrowed without
proving callee doesn't leak `self` — don't reuse blindly. NEXT (deferred per
owner, who chose merge-first): `arg` sub-census + a SEPARATE predicate
`param_value_is_consumed_only_by_inline_field_memcopy?` (definite recursive POD +
exact use_memcopy equivalence), rollout direct `field_store` first then exact
`arg_param_copy_field_only`. THEN Stage 1a flip (gated, default OFF, POD-only).

**2026-06-19 — Stage 0+ SHIPPED (`abi-struct-byvalue`, `b16bf758`): arg sub-census
+ by-value eligibility predicate.** Read-only/gated; suite 131/131 + 36/36; gate-OFF
compile behavior unchanged. New: `struct_type_is_recursive_pod?` (DEFINITE recursive
POD — recurses struct fields, rejects ref/array/union/proc/tuple/opaque, no optimistic
default; addresses finding 3), `classify_arg_param_consumption` +
`param_value_is_consumed_only_by_inline_field_memcopy?` (single-hop reason-coded:
rejects pointer-carrier store [finding 2], receiver call [finding 4], forwarding,
container, return), `field_store_site_is_inline?`, census splits. **Census (366 sites)
RESHAPES Stage 1a:** `arg` = 82 forwarded / 46 no_callee / **0 copy_field_only** — the
common `Particle.new(Vec2.new(..))` forwards through `.new`→`initialize`, so a one-hop
arg predicate flips NOTHING. `field_store` inline/carrier = 8/10 (step-4 OFF) → 17/1 (ON);
**flip_eligible = 6 (OFF) / 12 (ON)**, ALL from direct inline `field_store` (recursive-POD-
gated); coarse-POD over-count = 18 (confirms `struct_type_is_pod?` unfit). REVISED Stage 1a:
(1) flip direct inline `field_store` + recursive-POD FIRST (6/12 sites); (2) for `arg`,
add a one-hop `.new`→`initialize` forwarding trace OR flip at the forwarded callee — decide
after measuring `initialize`-side stores. NOT the whole arg bucket.

**2026-06-19 — Stage 1a brief WRITTEN (`c79446d4`, `docs/abi_byvalue_stage1a_brief.md`),
awaiting owner's GPT hostile review.** Verified ground truth: `Vec2$Dnew` mallocs 16B
(8B `i64` INT64_MAX GC/RC sentinel header at `ptr-8` + 8B payload, returns payload ptr);
the `-8` header is the rc_inc/rc_dec sentinel and structs are currently treated as STATIC
(never rc'd, leak to exit) → by-value PODs reaching an rc path are a no-op not a crash
(Darwin; glibc `malloc_usable_size(non-heap)` UB = hazard). **CRUX for review:** `T$Dnew`
return ABI is per-type-GLOBAL, so the per-site census (6/12) is a FLOOR — Stage 1a needs
Shape A (whole-type flip + new per-TYPE aggregation pass = Stage 0++) or Shape B (dual ABI
`T$Dnew$byval`). NEXT: adversary-verify GPT critique → pick Shape A/B → build per-type
aggregation + gated flip. Brief lists 7 hazards + DoD.

**2026-06-19 — GPT critique ADVERSARIALLY VERIFIED (brief §4a added).** GPT said A/B is a
false dichotomy because **Shape C** already exists (per-site stack promotion,
`lower_stack_local_struct_allocator_call` `hir_to_mir.cr:6163`, intercept `:3973`, ptr ABI
kept). Verified with 2 falsifiers (`--emit llvm-ir`, `ADAMAS_STACK_PROMO_TRACE=.new` — the
MIR name is `T.new$...`, `$Dnew` is backend-only mangling, so filtering "Dnew"=0 traces=false
negative). All GPT anchors CONFIRMED (6163/3973/3367/6320/llvm:294). **Falsifier 1**
(non-escaping local): `Particle.new`+`Vec2.new` PROMOTED, `alloca %Vec2`/`%Particle`, 0 malloc,
0 `$Dnew`, ptr sigs intact. **Falsifier 2** (escaping `arr << Particle.new(...)`): `Particle.new`
→ reject `ArgEscape` → heap `Particle$Dnew(24B)` + 2 inner `malloc64(16)` field-Vec2 slots; only
Vec2 temporaries promote. **VERDICT: Shape C real but VULNERABLE as the gap-closer** — the
~10×/~2× bench gap is escaping containerized Particles (`Array(Particle)`), which the lifetime
walker *correctly* rejects (outlive frame, cannot stack-promote). Shape C = verified no-op on the
bench. Real lever = container/escape VALUE ABI (Array stores inline struct values + sret/by-value
`$Dnew` for escaping PODs) = Shape A direction + per-type aggregation.

**3rd lever found + GPT anchors VERIFIED → PATH ORDER (revised).** Escaping `Particle$Dnew` does 3
mallocs: 1 Particle + 2 **dead default-init Vec2** per struct field — `alloc gc Type#911 size=8` +
memcopy into field, then `initialize` overwrites. Origin VERIFIED at `ast_to_hir.cr:29679` (regular)
+ `:30200` (overload): every struct-typed ivar with no usable default emits `Allocate(zero-struct)` +
`FieldSet` regardless of whether `initialize` fully sets it. MIR proof `/tmp/bench_mir_on.mir:65958/65961`
(both GPT anchors confirmed). PATH ORDER (was Shape-C-first; corrected per GPT): **(1) dead-default-init
elimination FIRST** (bounded slice, real perf signal, no Array-ABI change) — skip the zero-struct alloc
ONLY if `initialize` has a **dominating unconditional FieldSet** to that ivar before ANY read/escape;
REJECT on read-before-write (`log(@pos)`), self-escape-before-write (`register_self(self)`),
branch/return/raise before store, address-of self/field, union/fixup, non-POD/ref-owning field.
Gated default OFF + negative reducers + suite + s2b + bench malloc/RSS/time delta. **(2) container/escape
value ABI** later (the true final lever, too broad now: stride/return ABI/Array storage/self-host).
**(3) Shape C eligibility extension** optional cleanup (correctness-neutral, bench unchanged — proven).

**2026-06-19 — PATH ORDER step (1) dead-default-init elimination IMPLEMENTED + VERIFIED**
(branch `abi-struct-byvalue`). Gated
`ADAMAS_SKIP_DEAD_DEFAULT_INIT` (default OFF). New predicate
`initialize_unconditionally_sets_ivar?` (`ast_to_hir.cr`) scans ONLY initialize's
**entry block** (always-executes, straight-line — branches/returns/raises live in the
terminator or successor blocks, so any control flow auto-rejects): ACCEPT on a dominating
`FieldSet(self.@ivar, value!=self)` reached before any read/escape; REJECT on self-FieldGet,
Call/Yield carrying self, AddressOf/Cast of self, FieldSet storing self, or any unknown
instruction (whitelist). Wired into both zero-struct sites — regular `generate_allocator`
(init pre-lowered at the layout pre-lower) and `generate_allocator_overload` (lowers init
early via `lower_function_if_needed`, since it is otherwise lowered after the gate). Skipping
the `Allocate`+`FieldSet` is safe: the field memory already exists in the object `alloc`;
initialize overwrites it first. **DoD ALL MET:**
- Reducer `regression_tests/dead_default_init_elim_repro.sh`: gate OFF `Particle.new` = 2 dead
  Vec2 allocs, gate ON = 0; 3 negatives (read-before-write, self-escape, branch-partial) kept ≥1.
  Adversary trace confirmed negatives rejected by the **predicate** (`found=true skip=false`),
  not a trivial nil-func pass.
- Runtime correctness: single struct `pos=7,8 vel=9,10` and container sum identical ON vs OFF
  (the `Array(Particle)` sum also re-exposes the pre-existing container-aliasing bug = lever (i),
  untouched).
- Full suite gate OFF: ALL PASSED. Full suite gate ON: **131/131 + 36/36 ALL PASSED** (identical set).
- Bench (2M `Array(Particle)`): `Particle$Dnew` `__adamas_malloc64` **3→1** (−2/particle = −4M);
  whole-module malloc sites 6290→6275; peak RSS **150.3MB→85.95MB = −43% (−64MB ≈ predicted
  2·16B·2M)**; warm wall ~0.06s→~0.03s.
- s2b gate ON: **builds** (33.88MB, 18KB SMALLER than gate-OFF 33.90MB, 223s); behaves
  **identically** to gate-OFF s2b — both compile `x=1` cleanly (identical 88760B binary) and both
  SIGBUS (exit 138) on a struct program (= documented pre-existing GC two-heap crash, not fixed on
  this branch). NO regression from the gate.

Step (1) COMMITTED `8076254f` (`ast_to_hir.cr` + reducer + TODO).

**2026-06-19 — PATH ORDER step (2) prep: Stage 0++ per-type aggregation + enum refactor**
(`abi-struct-byvalue`, this commit; `hir_to_mir.cr` only). Two parts, ONE logical change:
- **Enum refactor (allocation-free classifiers):** the by-value classifiers
  (`classify_arg_param_consumption` is the hot-path one — runs per call site when the flip
  is enabled) now return ENUMS (`CtorFlow`/`ArgUse`/`RefinedBucket`/`ByvalTier`) instead of
  Strings — member compares, no per-site String garbage. Snake_case display labels derived
  ONLY at diagnostic print time (cold, gated census) via `#to_s.underscore`.
- **Stage 0++ (`run_struct_byvalue_type_aggregation`):** read-only/gated pass that folds
  per-SITE buckets into a per-TYPE verdict (`ByvalTier`), because `T$Dnew` is ONE function
  per type → its return ABI is per-type-GLOBAL. Prints `[BYVAL_TYPEAGG]` under
  `ADAMAS_STRUCT_BYVALUE_CENSUS`.
Claim scope (narrow, per GPT): **gate-OFF behavior-neutral** (census+typeagg output
byte-identical pre/post, suite 131/131 + 36/36, dead-default reducer green); gated census
diagnostics changed/extended (BYVAL_TYPEAGG now always prints under the census gate).
**Decision-grade finding:** Shape A (whole-type flip) is impractical as first step — `trivial`
tier (whole-type-flip-safe) is tiny + perf-irrelevant (Fiber::Context/Stack, CachedPowers::Power);
`Vec2` lands in `container` tier with MIXED flows (arg_forwarded=3 container=1 copy=1 return=1) →
a whole-type Vec2 flip must close container + arg-forward + return + copy ABIs at once (viral).
**Blocker found:** recursive-POD predicate has a nested-struct FALSE-NEGATIVE — `Pair{Vec2,Vec2}`
classifies `non_pod` (NOT a step-4 carrier artifact; `ADAMAS_INLINE_SMALL_STRUCTS=1` keeps it
non_pod). Root: struct-typed ivar's MIR field type_ref does not resolve back to the registered
struct in `struct_type_is_recursive_pod_mir?`.

**2026-06-19 — recursive-POD nested false-negative FIXED** (`abi-struct-byvalue`, this commit;
`hir_to_mir.cr` + new reducer). ROOT CAUSE (empirically pinned via a temp POD trace, then
reverted) was NOT a type_ref resolution miss (the earlier hypothesis above is WRONG):
`Pair{Vec2,Vec2}` resolves to `Struct/fields=2` fine. The bug: `struct_type_is_recursive_pod_mir?`
used `seen` as an ALL-VISITED set that was never popped, so `@a:Vec2` added Vec2's id and then
`@b:Vec2` (a SIBLING of the same POD type) hit the cycle guard and returned false → `Pair` wrongly
`non_pod`. FIX: `seen` is now the current DFS ANCESTOR-PATH set (id removed on the way back up) — a
real cycle is a type reachable from itself along the path, not the same POD used twice as siblings.
Also renamed `struct_type_is_recursive_pod?` → `struct_type_is_semantic_recursive_pod?` + doc note:
this is the SEMANTIC predicate (declared fields recursively bit-copyable; gates future value/container
ABI); a SEPARATE storage-aware predicate must gate memcpy/stack-promo on the current layout (else
lever-(i) container-aliasing UAF). DoD: reducer `recursive_pod_nested_sibling_repro.sh` (Vec2/Pair/
Quad=true, WithString=false); dead-default reducer green; suite 131/131 + 36/36; Stage 0++ rerun
(bench_struct_heap.cr) now classifies GC::Stats/Time::Instant/Pointer::Appender/DWARF::Register as
pod=true.

**2026-06-19 — ContainerElemRepr rename + stored-label PLUMBING SHIPPED** (`abi-struct-byvalue`; GPT
GO behavior-neutral plumbing-before-codegen). Hardens the scaffold per GPT round-2 before any lowering
change: (1) RENAME enum member `PointerSlot → ExistingLowering` — the fallback arm means "keep the
existing per-element lowering", NOT "the slot is a pointer" (primitives/wide-unions/primitive-tuples
are stored INLINE-by-value by the existing cascade `container_elem_storage_size_u64_impl`, so a literal
`when PointerSlot` would corrupt them); lowering sites must treat it as a passthrough. (2) STORE the
classification on `MIR::Type#container_elem_repr` (variant 1): classify ONCE during HIR→MIR via
`populate_container_elem_repr` (registry + HIR lib-set in scope, run late after sizes settle) and have
LLVM READ the stored label — LLVM has no `@hir_module.lib_structs`, and the lib reject is part of the
leaf-gate, so re-deriving in LLVM would lose lib-info and drift (Vec3 stride). Renamed compute
`container_elem_repr → classify_container_elem_repr`; census now READS the stored label. Still gated
`ADAMAS_INLINE_POD_CONTAINERS` (default OFF), behavior-NEUTRAL. DoD MET: reducer green
(Vec2/Vec3=InlineValueCopy, Pair/WithStr=ExistingLowering, families struct=InlineAddress, 410 unions
all ExistingLowering, gate OFF no [ELEM_REPR]); gate-OFF `--emit llvm-ir` BYTE-IDENTICAL to `ae479948`
(124 diff lines ALL non-det `stub_name` salts — prev-vs-prev same-binary AND cur-vs-prev both 124, 0
non-stub, normalized 0). NEXT (behavior-changing, ONE atomic gated slice, requires s2b): sizing for
InlineValueCopy + ALL store paths (emit_array_set, raw Array#<<:4453, Pointer(T)#<<:13837) + ALL load
paths (emit_array_get:25121, unsafe_fetch:4499) together; copy-on-load v1 = heap-copy ALWAYS through
the CURRENT carrier layout `[i64 header][payload]` via the strategy-aware allocator (llvm_backend.cr
:17708-17721; ARC=refcount 1, GC=INT64_MAX sentinel, return base+8 — NOT malloc(payload), else
rc_inc/rc_dec at ptr-8 corrupts); NO stack fast-path in v1. Reducers
copy-on-store/load/double-store/realloc-stride (12B Vec3) + s2b green.

**2026-06-19 — ContainerElemRepr classification SCAFFOLD SHIPPED** (`abi-struct-byvalue`; GPT GO
scaffold-only). First implementation slice of the storage brief, behavior-NEUTRAL: adds MIR
`ContainerElemRepr` enum (`PointerSlot | InlineAddress | InlineValueCopy`, mir.cr) + registry-backed
classifier `container_elem_repr` / `leaf_storage_pod_struct?` / `mir_struct_is_lib?` (hir_to_mir.cr) +
new gate `LayoutContract.inline_pod_containers?` (`ADAMAS_INLINE_POD_CONTAINERS`, default OFF). The
classifier is COMPUTED + LOGGED only (`[ELEM_REPR]` census under the gate); NO lowering site reads it
(container_elem_storage_size_u64 / emit_array_get / _set / Pointer(T)#<< / unsafe_fetch UNTOUCHED).
GATE = leaf-storage-POD (every field primitive/enum/raw-ptr, no nested struct/tuple/union/ref, ≤16,
non-union, non-lib), NOT semantic-POD. Family/leaf checks gated on `kind.struct?` (mirror
inline_container_struct_type? :2798) so a union named `Slice(..)|..` is NOT misread as a family.
DoD MET: reducer `container_elem_repr_scaffold_repro.sh` green (Vec2/Vec3=InlineValueCopy,
Pair/WithStr=PointerSlot, Slice/StaticArray/Hash::Entry struct=InlineAddress, 410 unions all
PointerSlot, gate OFF no [ELEM_REPR]); gate-OFF `--emit llvm-ir` BYTE-IDENTICAL to pre-step baseline
(only non-det `stub_name_<hash>` salt churn — 124 diff lines both base-vs-base AND base-vs-cur,
0 non-stub diffs, normalized identical); suite 131/131 + 36/36. s2b NOT required for scaffold (next
behavior-changing store/load commit). NEXT (behavior-changing): wire InlineValueCopy into the store
sites (Pointer(T)#<<:13837, raw Array#<<:4453, emit_array_new sizing) + copy-on-load
(emit_array_get:25121, unsafe_fetch:4499), gated, with copy-on-store/load/double-store/realloc-stride
(12B Vec3) reducers + s2b green.

**2026-06-19 — Option C: placement-fusion census axis SHIPPED** (`abi-struct-byvalue`;
`hir_to_mir.cr` +`run_struct_byvalue_fusion_census` + reducer `byvalue_fusion_site_census_repro.sh`).
Second, read-only census axis (gated `ADAMAS_STRUCT_BYVALUE_CENSUS`, behavior-neutral): counts
placement-CANDIDATE boxes = a user-struct ctor whose SOLE value use is a container write
(`classify_struct_ctor_flow == Container`), split semantic-POD (malloc 1→0 candidate) vs non-POD
(stays boxed). CANDIDATE axis, not proof: `container_write_call?` is method-name-based (#push/#<</
#[]=/#unsafe_put), so the count is an upper bound — each site still needs proving against the real
container storage ABI. KEY SIGNAL: prelude baseline = `removable_box_sites=4` (UInt128×3, DWARF
Attribute×1), `ineligible=1`, only `fresh_ctor=5` of `container_writes_total=1495`. So the isolated
`arr << T.new(...)` placement-fusion lever is RARE in self-host — fusion-first would barely move the
compiler. DoD: reducer green (Vec2=3, WithStr=1, named-local `arr << v` excluded); suite 131/131 +
36/36; gate-OFF byte-neutral. NEXT (per GPT, storage-first NOT fusion-first): scoped storage ABI
slice for `Array(LEAF-storage-POD struct ≤16B)` FIRST — brief
`docs/abi_byvalue_storage_slice_brief.md` (DESIGN checkpoint, GPT round-1 ROBUST). v1 = MIR
`ContainerElemRepr` enum (`PointerSlot | InlineAddress | InlineValueCopy`) + new gate
`ADAMAS_INLINE_POD_CONTAINERS` (default OFF, byte-identical) + copy-on-store + escape-aware
copy-on-load. GATE IS leaf-storage-POD (every field primitive/enum/raw-ptr, no nested
struct/tuple/union/ref, ≤16, non-union, non-lib), NOT semantic-POD: under step-4-OFF field ABI a
`Vec2` FIELD is a pointer carrier (`user_struct_inline?` = `size>8`), so `Pair{Vec2,Vec2}` payload =
two pointers → memcpy would copy pointers. semantic-POD is the FUTURE gate once field-inline (step-4)
lands. First impl PR must be NARROW: repr enum + gate + reducers (incl. 12B `Vec3` for the
`emit_array_new` >8 path), NO fusion, NO nested POD. Must-fix store/load sites: `emit_array_get:25121`
(copy-on-load gap), raw `Array#<<:4453` (store-ptr corrupts payload), `unsafe_fetch:4499`
(load-ptr returns interior). Placement fusion (`arr << T.new(...)`) lands later as a separate
sub-slice. Whole-type Shape A not practical as first step.

**2026-06-18 — #1 s2b startup crash FIXED (two-heap GC hazard, fix D).** Branch
`s2b-twoheap-gc-fix-D`, 7 edits all in `src/compiler/mir/llvm_backend.cr` (no
stdlib). The atomic byte-buffer allocator family is moved off the Boehm GC heap
onto libc so no live String/Builder/IO buffer survives only on a heap Boehm
cannot scan through libc containers (premature free -> `String#byte_at` SIGSEGV
at stage2 startup): `GC.malloc_atomic` -> `__adamas_malloc64` (libc calloc),
`GC.realloc` -> `__adamas_gc_aware_realloc` (GC_base-aware: Boehm blocks via
`GC_realloc`, libc blocks via libc realloc). Scanned `GC.malloc` (GMP, EventLoop
arena) stays on Boehm. The wrapper is emitted at the module epilogue only when a
reachable `ExternCall "GC_realloc"` exists (`gc_aware_realloc_needed?`) — the
same condition that links libgc, which fixes a link bug where GC-free programs
got `Undefined symbols: _GC_base, _GC_realloc`. Evidence: baseline pre-D s2b
SIGSEGVs on `x=1`; D-built s2b compiles `x=1` exit 0 ~1s, output links + runs
clean; regression suite 160/160 + 31/31; repro
`regression_tests/gc_aware_realloc_gating_repro.sh`. NEXT: E = ARC-owned String
(general-runtime reclamation; D's leak-to-exit semantics enable leak
measurement to inform E). Details in `LANDMARKS.md` (LM-S2B-TWOHEAP-FIX-D).

Latest bootstrap frontier (LM-624/625, 2026-05-23): produced `s2` builds
cleanly under the safe wrapper and passes focused no-prelude guards for
qualified nested module namespaces, `skip_file` require scanning, and
`typeof(Enumerable.element_type(...))` annotation normalization. The latest
hardening removed two generated-stage2 crash roots: `skip_file` macro
directive scanning no longer calls Regex-backed `String#sub` while recursively
loading requires, and fixed `element_type` prefix tables no longer use
`Array(String)#find`/`any?` block scans in HIR or semantic type-expression
resolution. LLVM emission also avoids a nilable `@current_func_params[i]?`
fetch in `current_func_param_index?`, which had allowed produced `s2` to
dispatch `Parameter#index` to an unrelated `#index` method after union
narrowing.

Boundary: full-prelude produced `puts 42` is still not clean. With
`/tmp/cv2_param_index_s2/cv2_s2`, the smoke reaches `lower_main: exprs=15` and
times out under a 360s safe wrapper at about 646MB RSS instead of crashing
during prelude parse, module/class registration, or `typeof(element_type)`
normalization. Treat the next root as a lower-main progress/time frontier, not
a parser-first bug. The non-fatal `CLI#file_sha256$String` MIR optimizer
arithmetic-overflow diagnostic remains during produced `s2` builds. Refuted:
adding readability guards inside normalizer helpers fixed a no-prelude reducer
but regressed full-prelude module registration; do not reapply that branch
blindly.

Container-layout side checkpoint (LM-626/LM-630, 2026-05-23): `Pointer(T)`
allocation, store/load arithmetic, realloc, clear, and copy/move helpers now
agree on the same container storage size for inline unions. This fixed
corruption in `Array(Pair | Nil)` and `Array(Pair | Int64)` where initial malloc
and shifted buffer compaction used 8-byte pointer slots while reads/writes used
24-byte inline union slots. The next tuple frontier was also fixed:
`Array(Tuple(Int64, Int64))#push` previously memcpy'd tuple bytes into
pointer-slot buffers while reads loaded each slot as `ptr`; tuple pointer-buffer
stores now persist a tuple copy and store the pointer. Release benchmark smoke
now matches original checksums for struct arrays, tuple arrays, class arrays,
nilable struct/class arrays, and mixed struct/int unions. Remaining performance
gap: tuple/class-heavy V2 cases still pay extra heap-pointer/allocation cost.

Pointer-copy stride checkpoint (LM-631, 2026-05-24): `Pointer(T)#copy_from`,
`copy_to`, `move_from`, and `move_to` now use the same V2 container element
storage size as Array buffers instead of logical `type_size(T)`. This fixed
`Array(ExprId)#dup` and `Array(tiny_struct)#dup`, where generated code copied
only 4 bytes per heap-struct pointer slot and truncated every other pointer.
Produced `s2` now emits `Array(ExprId)#dup` with `elem_size=8`, and the former
full-prelude require-scan segfault moves forward into module registration.

Stack-local struct constructor checkpoints (LM-661/662, 2026-05-24): generated
struct `.new` calls whose HIR result is `StackLocal` now lower directly to a
caller-local stack allocation. Trivial generated `initialize(@ivar, ...)`
bodies inline as direct field stores; non-trivial initializer bodies still use
the real `#initialize` call. Zero-fill is skipped only when the field-store
ranges exactly cover the struct storage, so padding bytes remain protected.
Escaping constructors still use the heap-backed generated allocator. The
no-prelude layout matrix keeps all checksums aligned with original Crystal and
improves the local/nested/yield struct hot-loop profile, but V2 still trails
original substantially.

Primitive tuple carrier checkpoint (LM-663, 2026-05-24): primitive/enum-only
tuples now use one inline container-slot ABI across `Pointer(Tuple(...))` and
`Array(Tuple(...))`. Allocation, indexed load/store, pointer add, realloc, and
LLVM Array get/set all agree on the MIR tuple byte size, while tuple carriers
containing refs, unions, or structs still use the legacy pointer-carrier path.
The no-prelude layout matrix now brings `pointer_tuple_stride` down to the
same V2 internal-tick class as the scalar baseline. Remaining structural
slowdowns are now concentrated in heap-backed struct pointer slots, nilable/mixed
union materialization, and optimizer parity.

Nested generic pointer-appender checkpoint (LM-652, 2026-05-24):
`Pointer::Appender(T).new(pointer)` now preserves its specialized nested
receiver through path receiver normalization and is no longer mistaken for the
primitive `Pointer(T).new(address)` shortcut in LLVM. The focused produced
binary oracle for `Pointer(UInt8)#appender` now initializes `@pointer`/`@start`,
pushes bytes, and reads the resulting slice successfully. Produced `s2` still
builds in about 154s with the existing non-fatal `CLI#file_sha256$String` MIR
optimizer overflow diagnostic; full-prelude produced-s2 `puts 42` still exits
139, now with trace output reaching later `Float` module registration.

String constructor safety checkpoint (LM-653, 2026-05-24): the
`String.new(UInt8*, Int32, Int32)` LLVM override now rejects non-positive,
null, and allocation-overflow byte counts before allocation or `memcpy`; the
UInt64 delegate now bounds-checks before truncation. This removes a verified
heap-corruption root where negative `bytesize` became a huge unsigned copy
length and could poison GC metadata with `[STAGE2_DEBUG]` bytes. Produced `s2`
still builds in about 154s, but full-prelude produced-s2 `puts 42` still exits
139; the current frontier has moved to class registration (`class register
idx=3/111` in the latest safe run), so continue with class-registration memory
and malformed byte-count source localization rather than treating this as a
complete s2b fix.

Built-in generic-base checkpoint (LM-654, 2026-05-24): contextual generic
resolution now preserves built-in generic bases such as `Array`, `Hash`,
`Tuple`, and `Pointer` instead of resolving plain `Array(T)` to sibling
compiler-internal names like `Crystal::MIR::Array(T)`. This fixes the generated
`Module#intern_type` bucket entry type (`Tuple(UInt8, Array(HIR::TypeRef),
HIR::TypeRef)`) and removes the produced-s2 no-prelude crash while interning
`Pointer(UInt8)`. Host guards for `Hash#to_a` block-return tuples and qualified
module namespaces pass, and produced-s2 passes the namespace no-prelude guard.
Boundary: full-prelude produced-s2 `puts 42` still exits 139 during early module
registration, so the next root remains full-prelude module-registration
state/memory, not generic-base tuple capture.

Nilable Proc union checkpoint (LM-655, 2026-05-24): HIR union construction now
preserves typed `Proc(...)` variants instead of canonicalizing them to bare
`Proc`, and proc shorthand argument normalization resolves `self` against the
concrete owner. This fixes the host HIR pollution where
`Hash(String, Crystal::HIR::ClassInfo)#[]` returned
`Crystal::HIR::ClassInfo | String` because `@block : (self, K -> V)?` lost its
proc signature and made `Proc#call` return `Void`/wrong fallback types. Host
guards for nilable proc unions, `Hash#to_a`, and qualified namespaces pass.
Produced `s2` still builds, and the full-prelude `puts 42` frontier now reaches
`fixup_inherited_ivars start` before a segfault; continue from that
memory/layout-sensitive fixup frontier, not from the erased-Proc return root.

Bare generic constructor checkpoint (LM-656, 2026-05-24): bare generic `.new`
inside generic methods now prefers the enclosing concrete generic return type
when the generic template base and arity match. This fixes the host-generated
HIR invariant break where `Array(String)#to_set : Set(String)` called
`Set(Array(String)).new$Array(String)` for stdlib `Set.new(self)`. The focused
no-prelude guard catches the same root with `Bag.new(self)` in a generic module,
and full host HIR now calls `Set(String).new$Array(String)`. Produced `s2`
still builds and passes the qualified namespace guard, but full-prelude
produced-s2 `puts 42` still fails in `fixup_inherited_ivars`; the fresh lldb
frontier is `Set(String)#each` called from
`invalidate_generated_allocator_state` / `invalidate_lowered_layout_functions`
during `align_all_class_ivars`. Continue there rather than revisiting
`Array(String)#to_set` or patching `.to_set`/`Set#hash` symptoms.

Nil-return block proc checkpoint (LM-657, 2026-05-24): raw block callback
materialization now honors callee `& : T ->` / `Proc(T, Nil)` contracts instead
of using the block body's incidental return type as the function-pointer ABI.
The no-prelude guard verifies that a block passed to `&block : String ->` can
return `Token.new` internally while the materialized `__crystal_block_proc`
still has return type `Nil` and explicitly returns nil. Full host HIR now shows
the previous `Set(String)#each` crash site in
`invalidate_generated_allocator_state` passing `Proc(String, Nil)` to
`Set(String)#each$block`, and produced `s2` reaches past
`fixup_inherited_ivars`. Current frontier: produced `s2` build now fails later
with `Worker 0: MIR opt error for Adamas::Compiler::CLI#file_sha256$String:
Arithmetic overflow`; continue there as the next root, not at allocator-state
Set iteration.

MIR constant-fold wrapping checkpoint (LM-658, 2026-05-24): integer constant
folding now uses wrapping add/sub/mul semantics for signed and unsigned MIR
integer ops, matching the LLVM integer instructions V2 emits. This fixes the
produced-s2 build failure where the optimizer evaluated the FNV-1a
`file_sha256` `UInt64` multiply with checked Crystal arithmetic and raised
`Arithmetic overflow`. The focused MIR optimizer spec covers the same FNV
offset/prime multiply. Produced `s2` now builds cleanly again. Current
frontier: produced-s2 full-prelude `puts 42` exits 139 during target compile,
with trace reaching `class register idx=3/92`; continue from class
registration state/memory, not MIR constant folding.

Module stripped-lookup checkpoint (LM-659, 2026-05-24): generic module stripped
name lookup is now maintained incrementally instead of rebuilding
`@module_defs_stripped_lookup` by iterating `@module_defs` during include
registration. This removes the produced-s2 full-prelude crash at
`String include Comparable(self)`, where the lazy cache rebuild/lookup corridor
returned an empty generic key and then crashed in `Hash(String, Array(...))`.
Nested module registration now bumps the module-def cache version as well.
Produced-s2 full-prelude `puts 42` now passes class registration,
constant registration, pass2 function registration, and inherited-ivar fixup,
then reaches `lower_main: exprs=12`; it is still not a clean compile and may
segfault or time out in the lower-main frontier. Continue from lower-main
demand/layout behavior, not from `String`/`Comparable` include registration.

LSP performance side checkpoint (LM-605, 2026-05-20): the background prelude
loader now has a single in-flight owner. Repeated foreground requests while
`@prelude_state` is still nil no longer spawn duplicate cache rebuilds. The
focused regression and full LSP suite are green. After LM-606, opt-in
`LSP_AST_CACHE=1` also reuses AST cache for unchanged foreground documents; keep
it opt-in until the existing ast-cache signature/completion deltas are resolved.
After LM-607, `LSP_AST_CACHE=1` composes with the prelude summary cache instead
of forcing a fallback full-prelude parse, and background prelude cache
hydration publishes rebuilt cache maps only after the cache state is complete.
After LM-608, warm project-cache foreground analysis no longer applies
project-cache `ExprId -> type` maps to freshly parsed opened documents, and
cached method summaries rehydrate parameter/overload metadata. The focused
project-cache semantic-fidelity regression is green for signature params,
member completion, and method definition routing against a no-cache baseline.
After LM-609, foreground definition requests no longer hard-fail solely because
background prelude hydration is still in flight; warm default and
`LSP_AST_CACHE=1` harness runs now keep `definition handle_completion` at 1
location.
After LM-610, warm project-cache foreground docs preserve filtered `require`
paths for on-demand semantic fallback without re-enabling eager background
dependency warming. After LM-611, the remaining first-hit bench-file default
no-AST-cache dependency-load cost was closed for the current harness:
`definition Lexer` stays around 0.5-1.2ms, `signature help Parser.new` stays
sub-millisecond to low-millisecond, and `completion parser.` stays around
9-12ms with source-backed private/protected method labels instead of collapsing
to the shallow 11-item cache summary or loading the dependency graph. After
LM-612, `LSP_AST_CACHE` is enabled by default with `LSP_AST_CACHE=0` and
config `ast_cache: false` opt-outs; warm default `server.cr` open is now about
150ms in the harness while the focused cache semantic-fidelity spec and full
LSP suite stay green. After LM-613, AST document symbols are collected lazily
on `textDocument/documentSymbol` instead of during `didOpen`; warm default
`server.cr` open is about 140ms in the harness, while document symbols remain
AST-backed when requested. After LM-614, foreground `didOpen`/`didChange`
preserve declaration indexes but stop eagerly building the child expression span
index; positional navigation falls back to the AST walk and the focused
regression keeps hover, definition, semantic tokens, and lazy document symbols
green. After LM-615, first full semantic-token requests avoid ignored trivia,
hash priority lookups, dedup allocation, and temporary String allocation during
name/member source-window searches; the warm harness now reports `server.cr`
semantic tokens around 122-126ms with server-side collection around 66ms and
JSON serialization around 14ms. After LM-616, the formatter stores only
non-whitespace tokens while preserving comments/newlines and uses direct
one-token lookahead; steady direct formatting of `server.cr` is about 68-70ms
instead of about 73ms. After LM-618, declaration-header hover bypasses the
generic foreground AST walk while keeping the foreground expression index lazy;
warm harness `hover handle_completion` now hits the method-declaration fast
path in about 1.5ms server-side and about 5.4ms client-side. After LM-619,
exact-text reopen restores recently closed document analysis and diagnostics
inside the same server process; the repeated harness `server.cr` open used by
the call-hierarchy scenario dropped from about 130-140ms to 13-31ms in the
measured runs. After LM-620, exact-text reopen also restores already-computed
semantic-token and formatting response JSON; a direct profile on `server.cr`
showed reopened formatting served at about 0ms, while reopened semantic tokens
avoid server collection/serialization and are then dominated by large-response
JSON parsing. After LM-621, the parser accepts nilable indexer postfix chains
such as `table[key]?.try { ... }` inside ternary true branches, removing the two
recoverable parser diagnostics from `src/compiler/hir/ast_to_hir.cr` that
blocked foreground AST-cache persistence. A stable-binary isolated LSP profile
created the AST cache on the first run and then loaded `ast_to_hir.cr` from it
on the second run, dropping measured first `didOpen` from about 2.5s to about
1.14s for that file. After LM-622, full semantic-token JSON responses for
large exact disk-backed documents persist across LSP processes behind a strict
compiler-fingerprint/mtime/size/text-match gate and a 64KB source-size floor.
The measured `ast_to_hir.cr` full-token request dropped from about 1028ms on
the first compute-and-save run to about 410ms on a fresh disk-cache-hit run in
the helper path; the remaining cost is dominated by handling/parsing the huge
JSON response. After LM-623, semantic-token full responses carry stable
`resultId`s and the server supports `textDocument/semanticTokens/full/delta`;
when a client already has the current result id, the repeated
`ast_to_hir.cr` request returns an empty 75-byte delta in about 0.9ms instead
of resending 1,276,950 encoded ints. After LM-624, the remaining first full
semantic-token request no longer pays the full frontend lexer cost for the
LSP-only lexical overlay. On `ast_to_hir.cr`, the lexer-oracle path measured
about 550.5ms collection / 314.1ms lexical, while the default byte scanner
measured about 315.1ms collection / 117.8ms lexical with the focused
semantic-token fixtures and full LSP suite green.
After LM-625, unchanged disk-backed foreground opens can use the loaded
project cache after AST-cache parsing instead of rerunning foreground
name-resolution on `didOpen`; full semantic analysis is materialized lazily
for precision features that need a current-AST identifier map. On
`ast_to_hir.cr`, a stable-binary isolated profile measured warm default
`didOpen` at about 548.0ms versus about 999.5ms with
`LSP_FAST_PROJECT_OPEN=0` on the same warm cache.
After LM-626, that same cached foreground-open path no longer queues a
redundant debounced `UnifiedProject.update_file` for unchanged text; warm
`ast_to_hir.cr` `didOpen` stayed about 529.3ms while shutdown dropped from the
old ~1.7s maintenance tail to about 12.8ms.
After LM-627, warm cached foreground opens for unchanged disk-backed files also
skip AST-cache deserialization on `didOpen`; the open stores project-cache
summaries in a lightweight empty-AST document state and materializes the AST,
or full foreground semantic analysis, only when the first request needs it.
On `ast_to_hir.cr`, an isolated safe-wrapper timing probe measured lazy cached
`didOpen` at about 280.8ms average versus about 1149.1ms with
`LSP_FAST_PROJECT_OPEN=0` on the same warm cache. Focused first-request guards
cover semantic tokens, signature help, prepare rename, document symbols, and
folding ranges after a lightweight open.
Refuted for the current one-file warm harness: project-cache load itself is not
the dominant `initialize` cost (`cache=~2.9ms`), and disabling project cache
pushes dependency analysis back into foreground `didOpen`; lazy-on-first
`ExprSpanIndex` makes first hover worse for the current one-file warm harness.
Remaining LSP latency and fidelity candidates are first precision-request
materialization when the cached open has no identifier map and JSON/client
handling for the first full semantic-token response before a client has a
current delta result id. After LM-628, the method-local member-completion gap
exposed by lightweight cached opens is closed for constructor assignments such
as `helper = Helper.new`: the constructor extractor now recognizes uppercase
identifier receivers while still rejecting lowercase `variable.new`.
After LM-629, unqualified method-call hover and definition no longer force
first foreground semantic materialization after a lazy cached open. On
`ast_to_hir.cr`, first hover/definition at
`class_name_from_node(member, source)` measured about 24-25ms and kept
`ast_loaded=false` / `identifiers=false`, instead of paying the earlier
~2.6-2.8s semantic materialization cost. Remaining LSP latency candidates are
now mostly request shapes that genuinely need identifier maps, member/qualified
call precision outside the text fast path, and first full semantic-token
response transport before a client has a current delta result id.
After LM-630, `adamas tool lsp` is available as a thin launcher for a
sibling `adamas_lsp` binary or `ADAMAS_LSP_SERVER`, and the VS Code
extension can be configured with `crystalv2.lsp.serverPath` plus
`crystalv2.lsp.serverArgs` while keeping the old default direct binary path.
After LM-631, cached lightweight opens also serve hover and definition for
constructor-assigned member calls such as `helper = Helper.new` followed by
`helper.value(2)` without foreground AST materialization, as long as the
receiver type resolves to a concrete source file.
After LM-632, the same constructor-assigned local receiver corridor also serves
member completion for `helper.` without foreground AST materialization when the
receiver type resolves to a concrete source file.
After LM-633, signature help for the same shape (`helper.value(`) also returns
the resolved method signature without foreground AST materialization.
After LM-634, cached lightweight opens also serve `textDocument/documentSymbol`
from persisted `SymbolSummary` rows without foreground AST materialization,
but only when the open buffer exactly matches the unchanged cached file.
After LM-635, the VS Code extension no longer hardcodes a repo-relative LSP
binary path: settings override discovery, configured paths must be executable,
and the default path is `crystal2 tool lsp` with fallbacks to `adamas` and
standalone `adamas_lsp`.
After LM-636, invalid project-cache entries no longer run through a background
startup reparse path. They are recorded as deferred foreground work, skipped by
background indexing, and cleared only after a successful foreground document
update. This removes the VS Code crash corridor where `bin/adamas_lsp`
could stack-overflow in the parser shortly after startup while reparsing an
invalid cached file.
After LM-637, hover on qualified paths and member accesses no longer loads the
dependency graph on the request path. On `src/adamas.cr`, the harness keeps
the `CLI`/`CLI.new`/`cli.run` hover corridor in the low-millisecond range and
the debug log shows no `Loading dependency` entries during hover. Definition
keeps the broader dependency-loading resolver.
After LM-638, the hover text fallback for unqualified method calls uses
call-site arity to choose between same-name overloads and source-backed
signature formatting preserves default parameter values. This fixes the
`Random::PCG32#new_seed` shape where hovering a two-argument call selected the
zero-argument overload.
After LM-639, the matching definition fast path also carries call-site arity
into source-text method location lookup and keys the method-location cache by
arity. On the real `pcg32.cr` stdio harness, the two-argument `new_seed(...)`
call now hovers as the parameterized overload and go-to-definition points at
that same overload instead of the zero-argument wrapper.
After LM-640, hover also recognizes bare zero-argument member calls whose method
name ends in `!`/`?`. The real `int.cr` `value.to_i8!` request now returns
`def to_i8! : Int8`; because that numeric conversion is generated, hover uses
a narrow synthetic signature rather than inventing a fake definition location.
After LM-641, definition for that generated conversion points at the real
primitive template in `primitives.cr`, and uppercase stdlib constants in macro
argument lists use a lexical source-text path. The real `int.cr`
`Number.expand_div [Float64], Float64` request now hovers as `struct Float64`
and defines to `float.cr`.
After LM-642, the `expand_div` call itself is covered too: no-parentheses
member calls with uppercase receivers resolve the receiver source and index
`macro` declarations, so hover returns
`macro expand_div(rhs_types, result_type)` and definition opens `number.cr`.
After LM-643, `Int#abs_unsigned`-style ternary branches are covered: `&-`
hovers as a wrapping primitive operator and `to_u8!` reaches the generated
conversion fallback even after a ternary `:`, with definitions anchored in
`primitives.cr`.
After LM-644, explicit `lib` receivers are covered by the source-text path:
`LibIntrinsics.popcount8(src)` now hovers as the `fun` declaration and defines
to the `fun` line instead of selecting the wrapper `def self.popcount8`.
After LM-645, `&-` definition responses include an explicit
`originSelectionRange` via `LocationLink`, so editors have the operator token
range needed for clickable-source decoration.
After LM-646, AST-owned unary/binary operators also emit semantic-token
`operator` ranges, and the disk semantic-token cache moved to v3 so unchanged
large stdlib files do not serve stale pre-operator-token JSON.
After LM-647, fully qualified uppercase receiver hover/definition stays
receiver-local: `Crystal::System::Time.instant` resolves to
`crystal/system/time.cr` and hovers as `def self.instant`, rather than falling
back to the nearby `def Time.instant` wrapper.
After LM-648, callable parameter hover preserves the source parameter
signature and parameter definition uses byte-offset-derived ranges instead of
trusting stale span columns. This fixes the `Comparable(T)#<` body hover on
`other` so it reports `other : T` and definition lands on the parameter name.
The VS Code language configuration also treats Crystal operator tokens such as
`&-` and `<=>` as word-pattern units, so the editor can decorate the same
operator span that the server already returns through hover, definition, and
semantic tokens.
After LM-649, DiamondDB's full `src/diamond_foundation.cr` open no longer
crashes the LSP server on scoped alias-head type names such as
`Plan::Replica`. The semantic resolver now transports through lexical alias
heads before resolving the rest of a `::` path, and an exact in-progress
type-name guard keeps true alias cycles from stack-overflowing.
After LM-650, semantic coloring now traverses `case`/`when` branches and the
fast lexical overlay recognizes the frontend's broader Crystal keyword set.
The exact DiamondDB SQL lexer slice now emits tokens for `private`, `loop`,
`.ord.to_u8`, `peek_byte_at`, receiverless `peek_byte`/`at_end?`, and
`!at_end? && peek_byte`; the semantic-token disk cache moved to v4 to avoid
stale large-file token JSON.

Spec-first bootstrap checkpoint (2026-05-08): `docs/specs/` now contains the
first executable contract slice for Crystal V2, modeled after the DiamondDB
spec-first workflow but scoped to compiler bootstrap rather than full language
standardization. The initial set defines the stage corridor, HIR name/type
literal invariants, generic-template registration policy, MIR call ABI, LLVM
emission rules, and a falsifier matrix. Use these specs as the default target
when fixing new frontiers: every meaningful root fix should either satisfy an
existing row in `docs/specs/05-falsifier-matrix.md` or add/update a row with a
small guard.

Self-hostile spec review checkpoint (2026-05-08): after LM-561, the spec layer
has explicit pressure for `[MISSING-FALSIFIER]` rows, a first original-vs-stage
semantic oracle rule, a concrete generic template key shape, a MIR static-call
shape guard brief, and `docs/specs/06-cli-output-contract.md` for the active
post-LLVM file-output/outer-rescue frontier. Do not treat `--emit llvm-ir`
success as evidence for normal binary output.
After LM-562, the CLI/output spec also contains the exact static-call reducer,
adjacent emit-vs-binary commands, and the required localization log points for
the next post-LLVM tail fix attempt.
After LM-563, the falsifier matrix no longer marks the full-prelude
generic/template `puts 42` frontier as the active `current` row; it is a
`pre-s2-clean` gate behind the no-prelude CLI/output tail.

Stage2 CLI output tail checkpoint (2026-05-08): after LM-564, produced `s2`
passes the no-prelude static-call reducer in both adjacent modes:
`--emit llvm-ir --no-link` and normal binary output. CLI/cache-tail closure:
binary mode now keeps LLVM IR generation in memory, writes the `.ll` file
through raw `LibC` fd IO outside `LLVMIRGenerator`, and the LLVM cache hash
path streams through raw `LibC.open/read/close` instead of `File.open`. The
last C2 root was not static-call lowering and not the backend output sink
alone: lldb showed the post-write crash entering
`compile_llvm_ir -> file_sha256 -> Dir.open` and calling `__adamas_raise`
with a nil exception object in produced `s2`. The deeper nil-exception/Dir.open
path remains a separate runtime/lowering risk, not solved by this CLI-tail fix.
New guard: `p2_stage2_cli_output_tail_no_prelude.sh`, passed on host and
produced `s2`. Boundary: this clears the active no-prelude CLI/output tail; the
full-prelude generic/template `puts 42` row remains the next `pre-s2-clean`
gate, not a solved smoke.

Bootstrap investigation process checkpoint (2026-05-08): after LM-565, the
process specs record the patterns learned from the C2 cycle. Missing trace
lines are not proof that a function was not entered; use lldb/breakpoints/IR
when practical. Small helpers in self-host critical paths require fresh
`s1 -> s2` evidence. Cursor/Grok/Spark output is candidate evidence only.
Cache/hash/filesystem tails are bootstrap runtime surface, not harmless
infrastructure. A gate-local root fix must name deeper subsystem roots that
remain open.

Stage2 nilable union-wrap codegen checkpoint (2026-05-15): after LM-566,
produced `s2` passes the focused no-prelude reducer `x : UInt32? = nil; if x;
1; else; 0; end` and the produced binary runs under `scripts/run_safe.sh`.
Root closure: ordered union descriptor registrations are carried into MIR, the
LLVM union-wrap path uses descriptor-backed scalar scans instead of
stage2-sensitive iterator/string reverse lookups, and union-derived temporary
names are sanitized with the existing local-name helper. New guard:
`p2_nilable_union_wrap_codegen_no_prelude.sh`, passed on host and produced
`s2`. Boundary: this does not clear full-prelude `puts 42`; produced `s2` still
times out under a 60s adversary check during early registration, and the broader
nilable short-circuit union-phi reducer remains open on produced `s2`. The
`s1 -> s2` build also still prints a non-fatal MIR optimizer overflow for
`Adamas::Compiler::CLI#file_sha256$String`.

Stage2 generic static type-param `new!` checkpoint (2026-05-19): after
LM-571, host lowering preserves include-derived concrete long type-param
bindings such as `EquivUint => UInt64` when they are real module type params,
and static calls requested on a concrete generic owner such as
`Direct(Int32, UInt64).f` reuse that requested-owner map instead of falling
back to the template owner `Direct(T, U)`. New guard:
`p2_generic_static_type_param_new_bang_no_prelude.sh`, passed on the host
compiler and rules out unresolved `U.new!` / `EquivUint.new!` stubs plus
void-returning lowered methods. Produced `s2` builds successfully and the
full-prelude `puts 42` smoke no longer stops at
`STUB CALLED: EquivUint$Dnew$BANG$$UInt64`; without the trace env it now stops
at `STUB CALLED: Indexable$LT$R$Hequals$Q$$Indexable_block`. Boundary: the new
no-prelude guard still cannot pass on produced `s2` because it hits that
separate `Indexable#equals?` block-stub frontier before IR emission. The
`ADAMAS_TRACE_CLASS_FRONTIER=1` diagnostic env perturbs the produced
full-prelude smoke into a pre-scan timeout, so prefer the untraced abort stub as
the next primary frontier unless the trace path is being debugged directly.

Stage2 included generic equality block checkpoint (2026-05-19): after LM-572,
host full-prelude lowering for `Array(Int32)#==` emits the concrete receiver
helper `Array(Int32)#equals?$Array(Int32)_block` instead of the generic
`Indexable(T)#equals?$Indexable_block` abort stub. New guard:
`p2_indexable_equals_block_receiver_rebase.sh`, passed on the host compiler.
Produced `s2` builds successfully under the standard 300s/4096MB `run_safe`
gate; the produced namespace guard still passes. A clean-vs-patched produced
comparison shows the old `Indexable#equals?` abort is gone: clean produced `s2`
aborts the static `new!` guard source at that stub, while patched produced `s2`
gets past it and exposes a later segfault. Boundary: a broad generic
included-module block rebase was refuted because it pushed the s2 build over the
4096MB cap. The accepted fix is equality-family scoped, not a general
block/proc closure. The current traced full-prelude `puts 42` frontier is now
`Crystal::SpinLock`, segfaulting after `concrete_after_pass0`.

Stage2 macro-included proc source-sink checkpoint (2026-05-19): after LM-573,
the produced `s2` no-prelude reducer for `macro included` no longer crashes in
`AstToHir#extra_sources_for_arena` through the `MacroExpander#reparse`
`source_sink` proc. Root closure: proc literal capture detection now recognizes
bare calls that require lexical `self` when they are not proc params or parent
locals, so `->(code) { store_extra_source(macro_arena, code) }` carries the
compiler receiver instead of passing null as `self`. New guard:
`p2_macro_included_proc_sink_self_capture_no_prelude.sh`, passed on host and
produced `s2`. A broader unconditional proc `self` capture was refuted because
it made produced `s2` crash during pass3 on unrelated no-prelude main programs;
keep the accepted fix tied to implicit receiver demand, not every proc literal.
Current full-prelude `puts 42` frontier moved past `Crystal::SpinLock` /
`Crystal::Once::Operation` source-sink crash. Untraced produced `s2` now
segfaults during module registration in
`Hash(String, MacroValue)#key_hash` from `assign_macro_iter_vars` /
`process_macro_for_in_module` / `record_constants_in_body`. With
`ADAMAS_TRACE_CLASS_FRONTIER=1`, the same smoke timed out in pre-scan under
the 60s gate, so the untraced lldb backtrace is the cleaner next anchor.

Stage2 module macro-for iter-var checkpoint (2026-05-19): after LM-574,
macro-for iter variable names inside HIR module/class/lib/enum handling are
read through `safe_slice_to_string` and validated as identifiers before they
are used as `Hash(String, MacroValue)` keys. Root closure: produced `s2` was
constructing corrupted `String` keys with raw `String.new(slice)` in
`process_macro_for_in_module`, then crashing in
`Hash(String, MacroValue)#key_hash` during `assign_macro_iter_vars`. New guard:
`p2_module_macro_for_iter_var_names_no_prelude.sh`, passed on host and
produced `s2`; the prior proc source-sink and namespace guards still pass on
produced `s2`. Produced `s2` also builds successfully under the standard
300s/4096MB gate. Boundary: this clears the focused module macro-for hash-key
crash, not full-prelude `puts 42`. The full-prelude smoke now reaches module
register idx=51/114 untraced; lldb did not reach the crash under the 90s safe
timeout. With the trace env it reaches File error nested classes before exiting
133. A source-backed macro-for iter-var fallback was refuted because it made the
`s1 -> s2` compiler build fail during pass3 with an `ExprId out of bounds`
diagnostic; do not reapply that branch blindly.

Stage2 single-var macro-for binding checkpoint (2026-05-19): after LM-575,
produced `s2` no longer crashes on one-variable module macro-for reducers such
as `{% for name in %w(alpha beta) %}` while binding the loop variable into
`Hash(String, MacroValue)`. Root closure: the one-variable fallback path in
`assign_macro_iter_vars` used a direct `vars[iter_vars[0]] = value` shape that
generated an unstable produced-s2 `Hash#[]=` call, while the indexed loop shape
used by pair/tuple binding was stable. The fix routes the one-variable case
through an indexed `each_with_index` loop without adding any visible macro
variables. The `p2_module_macro_for_iter_var_names_no_prelude.sh` guard now
covers single-var generated defs, pair-var generated defs, and single-var
nested struct output; it passed on host and produced `s2`. Produced `s2` builds
successfully under the standard 300s/4096MB gate. Boundary: full-prelude
`puts 42` no longer reaches the `Hash(String, MacroValue)#key_hash` stack under
the tested trace path; it now times out in pre-scan under 45s/120s gates.

Stage2 unbound type-param scan checkpoint (2026-05-19): after LM-576,
produced `s2` no longer crashes in `Regex::MatchData#byte_end` while checking
include-derived method annotations such as `Array(T)` for unbound type
parameters. Root closure: `unbound_type_params_from_type_name` used
`String#scan(Regex)`, and produced `s2` can crash in the Regex match-data path
during class/module registration. The replacement is a direct byte tokenizer
for capitalized identifier tokens, matching the existing bootstrap rule to
avoid Regex in hot self-hosted paths. New guard:
`p2_unbound_type_param_scan_no_regex_no_prelude.sh`, passed on host and
produced `s2`. Produced `s2` builds successfully under the standard
300s/4096MB gate. Boundary: full-prelude `puts 42` now completes module
registration and reaches class registration before exiting 133; lldb under the
60s safe gate did not capture that moved class-register frontier.

Stage2 static-call LLVM emission checkpoint (2026-05-08): after LM-559,
produced `s2` no-prelude LLVM IR for `Exception::CallStack.skip("x")` now emits
the named static callee
`Exception$CCCallStack$Dskip$$String` with a valid `void` return ABI, not
fallback `@func1` and not `call  @...`. Root closure: preserve forced static
class-method names in HIR recovery, lower exact static calls before treating
stale receiver values as runtime receivers, and use dense FunctionId lookup in
LLVM emission because self-hosted hash lookup can miss. New guard:
`p2_stage2_static_call_named_llvm_no_prelude.sh`, passed on host and produced
`s2` and validated by `llc` when available. Boundary: produced `s2`
no-prelude binary output for the reducer still exits 139 after LLVM finalizes
output, so the next root is the separate CLI/file-output tail or outer-rescue
frontier, not the static-call callee/ABI spelling.

Stage2 type-literal name-query checkpoint (2026-05-06): after LM-558, produced
`s2` LLVM no longer contains `Bool$Dto_s` / `Bool$Dname` abort stubs. Root
closure: type-literal receivers such as stdlib `Pointer(T)#to_s` using
`T.to_s`, and direct `Bool.to_s` / `Bool.name`, now lower to a compile-time
type-name string unless a real dot-method override exists on the owner/parent
chain. New guard: `p2_type_literal_name_query_no_stub.sh` now uses a
no-prelude `NameProbe` type-literal method body, so it checks the name-query
lowering invariant without mixing in full-prelude registration. Boundary: this
is a shape/root fix, not a clean full-prelude smoke. Produced `s2` full-prelude
`puts 42` still exits 139; with the refuted source-backed top-level
return-annotation experiment reverted, the current untraced frontier reaches
pass2 `register_functions idx=3/297` and crashes before the next clean phase
log. Do not reapply the top-level source-return hunk blindly; with the
type-literal fix it still regressed the smoke to an earlier class-registration
crash around `class register idx=51/104`.

Stage2 Char::Reader post-registration frontier (2026-05-06): after LM-557,
produced full-prelude `puts 42` got past the previous `Proc` class-body trap.
That checkpoint remains useful historical evidence for the semantic
check-only/source-provider corridor, but LM-558 is the fresher active frontier.

Stage2 nested-method annotation namespace checkpoint (2026-05-05): produced
`cv2_s2` no longer qualifies top-level/builtin method annotations inside
`Float::FastFloat` as fake nested types. Root shape: after the self-wrapper fix,
full-prelude trace showed `Float::FastFloat.to_f64?` and `to_f32?` signatures
with `raw=String resolved=Float::FastFloat::String` and `raw=Bool
resolved=Float::FastFloat::Bool`. `DEBUG_TYPE_EXISTS_TRACE` showed the
candidate existed through an enum table hit, so `qualify_method_annotation...`
trusted a registry fallback rather than the structural nested-type set. Root
fix: for unqualified top-level/builtin annotations, keep the top-level name
unless the active namespace chain structurally records that nested type. Evidence:
`/private/tmp/cv2_annot_structural` host build; `p2_qualified_module_namespace_no_prelude.sh`,
`p2_nested_module_registration_no_prelude.sh`,
`p2_self_nested_module_registration_frontier.sh`, and
`p2_full_prelude_generic_template_namespace_no_pollution.sh` pass on host;
`scripts/run_safe.sh /private/tmp/cv2_annot_structural 300 4096
src/adamas.cr -o /private/tmp/cv2_annot_structural_s2/cv2_s2` exits 0; and
`p2_full_prelude_generic_template_namespace_no_pollution.sh` passes on produced
`/private/tmp/cv2_annot_structural_s2/cv2_s2`. Boundary: produced full-prelude
`puts 42` still times out in class registration after `class register idx=3/104`,
so the next root is liveness/registration cost past the now-correct
`Float::FastFloat` signatures, not the `String`/`Bool` annotation pollution.

Stage2 self-nested module wrapper checkpoint (2026-05-05): generated `cv2_s2`
now passes the module-registration trap that followed the pre-scan fix. Root
shape: produced `s2` can represent a qualified reopen wrapper as a nested
`ModuleNode` whose canonical name is the current owner itself
(`Float::FastFloat -> Float::FastFloat`). Routing that node back through
ordinary nested-module registration recurses into the same canonical owner and
hits a Trace/BPT trap during full-prelude `puts 42`. Root fix: self-wrapper
module names are removed from nested-name visibility, recursive self module
registration is skipped, and direct nested types/aliases carried by that wrapper
are still registered under the owner so the `ParsedNumberStringT` namespace
guard stays intact. Evidence: `/private/tmp/cv2_self_nested_final` host build;
`p2_qualified_module_namespace_no_prelude.sh`,
`p2_nested_module_registration_no_prelude.sh`, and new
`p2_self_nested_module_registration_frontier.sh` pass on the host compiler;
`scripts/run_safe.sh /private/tmp/cv2_self_nested_final 300 4096
src/adamas.cr -o /private/tmp/cv2_self_nested_final_s2/cv2_s2` exits 0; and
`p2_qualified_module_namespace_no_prelude.sh` plus
`p2_self_nested_module_registration_frontier.sh` pass on the produced compiler.
Refuted variant: recursively flattening self-wrapper module bodies into the
owner was too broad and moved produced `s2` back to an early module-register
Trace/BPT trap. Boundary: produced full-prelude `puts 42` now passes module
registration under the frontier guard, but the wider clean `puts 42` compile is
not yet an `s2 -> s3` unlock; suspicious parameter types such as
`Float::FastFloat::String` / `Float::FastFloat::Bool` remain the next root
pattern to localize.

Stage2 pre-scan constant frontier checkpoint (2026-05-05): generated `cv2_s2`
passes CLI class/module constant pre-scan for full-prelude `puts 42`. Root fix:
pre-scan keeps complex RHS constants name-visible without performing
registration-time literal/type/deferred-init work, while scalar Number/Bool/Char
constants still get full metadata early enough for ivar defaults such as
`IO::DEFAULT_BUFFER_SIZE`. Evidence: `/private/tmp/cv2_prescan_final` host
build; `p2_macro_compare_versions_control_no_raw_sanitize.sh`,
`p2_qualified_module_namespace_no_prelude.sh`, and
`p2_prescan_complex_constants_frontier.sh` pass on both the host compiler and
produced `/private/tmp/cv2_prescan_final_s2/cv2_s2`; and s1 -> s2 build exits 0
under `scripts/run_safe.sh`. Refuted variants: all name-only pre-scan and
`TypeRef::VOID` placeholders in `@constant_types` both lead to invalid LLVM
`store ptr 32768`.

Stage2 source-backed initializer-parameter checkpoint (2026-05-01): class and
module registration now avoid another stale frontend-slice boundary when
capturing `initialize` params into ivars. `capture_initialize_params` reads
parameter names and type annotations from `name_span` / `type_span` through the
member/source arena before falling back to guarded slices, and its registration
callers now pass the relevant arena explicitly. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_param_source_candidate
--error-trace`; `regression_tests/p2_enum_class_setter_return_infer_no_prelude.sh
/tmp/cv2_param_source_candidate`;
`regression_tests/p2_nested_module_registration_no_prelude.sh
/tmp/cv2_param_source_candidate`;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_param_source_candidate`;
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/tmp/cv2_param_source_candidate`; and `scripts/run_safe.sh
/tmp/cv2_param_source_candidate 300 4096 src/adamas.cr -o
/tmp/cv2_direct_param_source_candidate/cv2_s2`, which builds generated
`cv2_s2` in ~160s. Boundary: generated `cv2_s2` plain `puts 42` smoke still
segfaults during full-prelude module registration near
`Exception::CallStack` / `each_param(Array(Parameter), &block)`, so this is not
an `s2 -> s3` unlock yet.

Stage2 implicit-ivar param scan checkpoint (2026-05-01): generated `cv2_s2`
now advances past the previous `Exception::CallStack` implicit-ivar scan crash.
Root fix: the post-mixin implicit ivar discovery pass no longer scans every
method's parameter array looking for `param.is_instance_var`; it first checks
the source `def` header for an `@` parameter and only falls back to old
Parameter-field scanning if source is unavailable. Real `@param` names/types
are read from source-backed parameter spans. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_ivar_param_source_candidate
--error-trace`; existing p2 no-prelude guards; new
`regression_tests/p2_implicit_ivar_param_source_scan_no_prelude.sh
/tmp/cv2_ivar_param_source_candidate`; and `scripts/run_safe.sh
/tmp/cv2_ivar_param_source_candidate 300 4096 src/adamas.cr -o
/tmp/cv2_direct_ivar_param_source/cv2_s2`, which builds generated `cv2_s2` in
~161s. Boundary: generated `cv2_s2` plain `puts 42` smoke still segfaults, but
`DEBUG_REG_CONCRETE_PHASE=CallStack` now reaches `after_new_register`; lldb
shows the new frontier is a different `each_param` block inside
`register_nested_module_in_current_arena`.

Stage2 nested-module parameter checkpoint (2026-05-01): the
`register_nested_module_in_current_arena` PASS 2 class-method registration path
now resolves parameter annotations from source-backed `Parameter#type_span`
instead of direct `param.type_annotation` slices when a member arena is known.
Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_nested_module_params_candidate --error-trace`; the five p2 no-prelude
guards including `p2_implicit_ivar_param_source_scan_no_prelude.sh`; and
`scripts/run_safe.sh /tmp/cv2_nested_module_params_candidate 300 4096
src/adamas.cr -o /tmp/cv2_direct_nested_module_params/cv2_s2`, which
builds generated `cv2_s2` in ~155s. Boundary: generated `cv2_s2` still fails
plain full-prelude `puts 42`, but lldb no longer shows `each_param` /
`safe_slice_to_string`; the next frontier is
`infer_type_from_expr_inner -> infer_concrete_return_type_from_body` while
registering `Float::Float::Bigint`.

Stage2 initialize-return checkpoint (2026-05-01): class `initialize` methods
now keep the semantic `Void` contract in both registration and actual method
lowering. Root cause: registration was hardened first, but `lower_method` still
treated unannotated `initialize` like an ordinary implicit-return method, merged
the final body expression from Return terminators / `last_value`, and rewrote
HIR signatures such as `Box#initialize$Int32` to the body type (`Bool` in the
new no-prelude reducer). The fix makes `initialize` return `TypeRef::VOID`
before function creation, skips annotated/implicit return re-inference for
constructors, and emits a valueless implicit return terminator. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_initialize_void_candidate
--error-trace`; `regression_tests/p2_initialize_return_void_no_prelude.sh
/tmp/cv2_initialize_void_candidate`; the five existing p2 no-prelude guards;
and `scripts/run_safe.sh /tmp/cv2_initialize_void_candidate 300 4096
src/adamas.cr -o /tmp/cv2_direct_initialize_void/cv2_s2`, which builds
generated `cv2_s2` in ~162s. Boundary: generated `cv2_s2` plain full-prelude
`puts 42` smoke now reaches module registration and aborts on the next frontier,
`STUB CALLED:
Crystal$CCMIR$CCUnionDescriptor$Hinitialize$$String_Array$LCrystal$CCMIR$CCUnionVariantDescriptor$R_Int32_Int32`.
Do not treat this as an `s2 -> s3` unlock yet; next work should localize the
missing `UnionDescriptor#initialize` demanded symbol rather than changing
constructor semantics again.

Stage2 macro-expanded parameter source checkpoint (2026-05-01): the
`UnionDescriptor#initialize` abort was a stale source-recovery bug, not a
missing constructor feature. `MacroExpander#reparse` retains generated macro
output as an arena extra source but still reparses into the macro-definition
arena, so `parameter_name_string` / `parameter_type_annotation_string` could
slice `src/stdlib/macros.cr` or macro-body text instead of generated output.
The fix tries recent retained macro outputs for the same parameter span before
trusting the primary arena source, with bounded name/type candidate checks and
explicit `ArenaLike` narrowing at the helper callsite to avoid a generated-s2
nilable-helper abort stub. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_macro_param_source_candidate3 --error-trace`;
`regression_tests/p2_macro_extra_source_param_recovery_no_prelude.sh
/tmp/cv2_macro_param_source_candidate3`; existing p2 guards
`p2_initialize_return_void_no_prelude.sh`,
`p2_implicit_ivar_param_source_scan_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`,
`p2_nested_module_registration_no_prelude.sh`,
`p2_enum_class_setter_return_infer_no_prelude.sh`, and
`p2_visibility_private_accessor_no_prelude.sh`; and
`scripts/run_safe.sh /tmp/cv2_macro_param_source_candidate3 300 4096
src/adamas.cr -o /tmp/cv2_direct_macro_param_source3/cv2_s2`, which builds
generated `cv2_s2` in ~153s. Boundary: generated `cv2_s2` plain full-prelude
`puts 42` no longer hits `UnionDescriptor#initialize` or the helper stub; the
new frontier is `[INFER_INDEX] method=unlock
self=Exception::Exception::CallStack obj= idxs=1` followed by a segfault during
module registration. Do not attempt `s3b+` until that frontier is reduced.

Stage2 no-prelude semantic-corpus checkpoint (2026-05-01): generated `cv2_s2`
now compiles and runs `regression_tests/bootstrap_semantic_corpus.cr
--no-prelude` after the HIR inline-yield/proc-literal corridor and the MIR/LLVM
backend state were hardened. Root fixes in this checkpoint: inline-yield stack
ivars are explicitly initialized because generated stage2 can miss inline
defaults; inline-yield callee arenas are resolved through a non-nil
`function_def_arena_or_current`; `function_namespace_override_for` uses fixed
arity overloads instead of a splat helper that stage2 materialized as an abort
stub; proc-literal capture name/type arrays are built with explicit loops and a
non-nil arena; unary `&expr` is treated as the parser block/proc-pass marker
instead of a runtime unary method call; MIR pre-scans avoid stdlib `map/each`
over `Array(Tuple(ValueId, ValueId))` phi/switch arrays; LLVM backend caches the
current function's canonical param name/type pairs while emitting the signature;
and pointer-return emission now passes through already-pointer values instead
of generating invalid `inttoptr ptr ... to ptr`. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_clean_candidate --error-trace`;
`scripts/run_safe.sh /tmp/cv2_clean_candidate 300 4096 src/adamas.cr -o
/tmp/cv2_s2_clean`; `scripts/run_safe.sh /tmp/cv2_s2_clean 30 2048
--no-prelude regression_tests/bootstrap_semantic_corpus.cr -o
/tmp/cv2_clean_corpus`; and `scripts/run_safe.sh /tmp/cv2_clean_corpus 5 512`.
Boundary: this is a focused no-prelude oracle, not a full `s2 -> s3` proof.
Next work should add more fast no-prelude oracles around inline yield, proc
literal block pass, phi/switch MIR pre-scans, and pointer-return coercion before
promoting to a wider bootstrap ladder.

Stage2 container/arena/backend checkpoint (2026-05-01): generated `cv2_s2`
now builds again after several root-cause fixes in the container storage and
mixed-union ownership corridor. Fixed evidence-backed issues: `Array(Slice(UInt8))`
registered its element from an early `Generic Slice(UInt8)` alias instead of
the later concrete `Struct Slice(UInt8)` descriptor; broad inline struct-array
storage corrupted pointer-shaped frontend structs such as `Array(Parameter)`;
mixed unions like `Array(Parameter) | ExprId` failed to transfer ownership of
reference payload variants, so parser-returned arrays could be `rc_dec`'d while
stored in the union; function-name suffix rewriting sent literal `$arity...`
through `String#sub` regex replacement; V2 heap `Slice(UInt8)` validation only
probed the first bytes before `String.new(slice)`; module arena validation used
the recursion depth cap as a hard mismatch and could trigger repeated source
reparse repair for deeply nested namespace modules; GEP dynamic index conversion
could emit self-referential SSA names in no-prelude interpolation. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_gep_selfref_candidate
--error-trace`; `regression_tests/p2_array_struct_unsafe_fetch_return_no_prelude.sh
/tmp/cv2_gep_selfref_candidate`; `regression_tests/p2_pending_budget_no_prelude.sh
/tmp/cv2_gep_selfref_candidate`; `scripts/run_safe.sh
/tmp/cv2_gep_selfref_candidate 30 1024
regression_tests/combined/test_no_prelude_interpolation.cr --no-prelude -o
/tmp/cv2_gep_selfref_interp_bin`; `scripts/run_safe.sh
/tmp/cv2_gep_selfref_candidate 120 4096
regression_tests/complex/test_array_map_select_chain.cr -o
/tmp/cv2_gep_selfref_plain_smoke`; and
`BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2_post_7d99340f BOOTSTRAP_CHAIN_STAGES=2
BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2_post_7d99340f`,
which builds generated `cv2_s2` in ~219s and now passes `smoke no-prelude`.
Boundaries: `s2` plain smoke still segfaults during nested module registration;
the latest lldb trace on `/tmp/cv2_bs_s2_post_7d99340f/cv2_s2` shows stack
overflow in `GC_clear_stack_inner`, reached through repeated
`with_reparsed_module_from_current_source -> register_nested_module` recursion
while parsing a generic type annotation in a nested module. Stochastic stage2 build OOBs
with ASCII-like ExprId payloads (`[S2_`, `shad`) were observed in wrapper runs
but not reproduced under direct `run_safe` with `DEBUG_EXPR_OOB=1`; treat them
as suspected memory corruption, not verified root cause yet.

Stage2 source-backed extern registration checkpoint (2026-04-30): generated
`cv2_s2` now advances past the LibC registration abort stubs for
`extract_alias_name_value_from_source`, `register_extern_fun_from_source`, and
`resolve_extern_fun_signature_from_source`. The root was a helper ABI mismatch,
not a missing LibC case: source-backed extern helpers threaded `ArenaLike`
through generated-stage2 calls even though all local callers used the current
`@arena`, and the signature resolver mixed lib and top-level contexts through
`lib_name : String?`. Generated stage2 then emitted concrete `$String...` calls
while lowering materialized only broader `$Nil | String...` targets. The fix
adds the alias/extern source helper family to exact-demand, removes redundant
`ArenaLike` parameters from the local source extern helpers, and splits lib
extern signature resolution (`String` lib name) from top-level `fun`
resolution (no lib-name parameter). Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_source_extern_split_candidate
--error-trace`; `regression_tests/p2_source_extern_signature_no_prelude.sh
/tmp/cv2_source_extern_split_candidate`; and
`BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2_source_extern_split
BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out
/tmp/cv2_bs_s2_source_extern_split`, which builds generated `cv2_s2` and keeps
`smoke no-prelude: ok`. Boundary: full-prelude `s2` smoke is still not clean;
the next exposed frontier is
`Hash(String, Hash(UInt32, Crystal::HIR::Value))#to_unsafe` during LibC
registration. Also keep the broader requested-symbol-wrapper issue open:
when a concrete call symbol resolves to a wider typed overload, lowering may
still need to materialize a requested-name wrapper instead of only the wider
target.

Stage2 bounded String-search checkpoint (2026-04-30): the generated `cv2_s2`
`private class Hidden` no-prelude reducer no longer dies in
`lookup_function_def_for_call -> String#includes?` because the LLVM backend
now emits bounded `memcmp` loops for `String#includes?(String)` and
`String#index(String, offset)` instead of passing Crystal's length-delimited,
non-NUL-terminated payloads to libc `strstr`. The helpers also fail closed on
null operands so the self-hosted compiler does not crash before exposing the
real next frontier. Evidence so far: `crystal build src/adamas.cr -o
/private/tmp/cv2_string_nullsafe_candidate --error-trace`;
`regression_tests/p2_string_bounded_search_runtime_repro.sh
/private/tmp/cv2_string_nullsafe_candidate`;
`regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
/private/tmp/cv2_string_nullsafe_candidate`; and
`scripts/run_safe.sh /private/tmp/cv2_string_nullsafe_candidate 300 4096
src/adamas.cr -o /private/tmp/cv2_s2_string_nullsafe`, which builds the
next generated compiler. Boundary: this is not a full nilable/short-circuit
codegen fix. Two `lower_call` hot paths now use explicit local narrowing for
`full_method_name`, but the broader self-hosted nilable guard issue remains
open. Generated `cv2_s2` now advances the simple `String#includes?("$$block")`
and `private class Hidden` no-prelude reducers from String segfaults to
existing Hash-stub aborts (`Hash#each` and
`Hash(String, Array(Tuple(String, Crystal::MIR::Function)))#<<$String`).
Treat those Hash stubs as the next root-cause frontier before attempting
`s2 -> s3`.

Stage2 self-host visibility/arena frontier update (2026-04-30): the
`private DIGITS_DOWNCASE` failure is no longer a visibility allowlist problem.
The parser now recognizes uppercase identifier assignment through a concrete
`IdentifierNode` path and ASCII byte check, and deferred constant
initializers now store an arena-stable `ExprId`+arena record instead of a raw
`Int32` index. Generated `cv2_s2` now compiles the no-prelude reducer
`private VALUE = 1; VALUE` and registers it as a constant. The next exposed
family is self-host exact-signature drift around arena helpers: generated
calls may be `Nil | AstArena | PageArena | VirtualArena` while the intended
helper contract is `Frontend::ArenaLike`. Several reparsing/class-registration
helpers now normalize nilable arenas explicitly and avoid `map/find` block
helpers on reparsed roots. Evidence so far: `crystal build
src/adamas.cr -o /private/tmp/cv2_cast_candidate --error-trace`;
`regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
/private/tmp/cv2_cast_candidate`;
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/private/tmp/cv2_cast_candidate`;
`regression_tests/p2_splat_default_args_no_prelude.sh
/private/tmp/cv2_cast_candidate`; and
`regression_tests/p2_visibility_private_const_module_no_prelude.sh
/private/tmp/cv2_cast_candidate`; plus the same
`p2_visibility_private_const_module_no_prelude.sh` run against generated
`/private/tmp/cv2_bs_s2_cast/cv2_s2`; and
`BOOTSTRAP_STAGE_OUT=/private/tmp/cv2_bs_s2_cast
BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out
/private/tmp/cv2_bs_s2_cast`, which builds generated `cv2_s2` and keeps
`smoke no-prelude: ok`. Boundary: generated `cv2_s2` now passes no-prelude
`private module M; end` and `private VALUE = 1`, but
`private class Hidden; def value; 1; end; end; Hidden.new.value` has advanced
past registration stubs and now segfaults in `lower_main` through
`lookup_function_def_for_call -> String#includes?`. Full-prelude `s2` smoke
still segfaults at `top-level collection walk start`; do not claim full
visibility-class support until the generated no-prelude `private class` reducer
is green.

Stage2 full-prelude frontier update (2026-04-30): three root fixes are ready
as the next green commit, but full-prelude `s2` smoke is still not clean.
First, default-argument expansion now preserves the actual named-argument
signal and returns the concrete overload selected before defaults; splat packing
uses that selected overload instead of re-resolving the generic base after
scalar defaults. This removes bad scalar wrappers such as `Dir.glob$String` and
`Dir.glob$String_File::MatchOptions_Bool`. Second, MIR now indexes Proc carrier
provenance across class variables, so raw C function-pointer callbacks returned
by extern calls and stored in class vars (for example GC push-root callback
hooks) are not later called as heap Proc objects. Third, `private/protected
abstract def` now preserves visibility in the parser instead of wrapping the
abstract modifier and losing the method visibility. Evidence so far:
`crystal build src/adamas.cr -o /private/tmp/cv2_commit_candidate
--error-trace`; `regression_tests/p2_splat_default_args_no_prelude.sh
/private/tmp/cv2_commit_candidate`;
`regression_tests/p2_selfhost_stage2_shape_guard.sh
/private/tmp/cv2_commit_candidate`; `regression_tests/p1_mixed_proc_block_yield_carrier.sh
/private/tmp/cv2_commit_candidate`; and
`regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
/private/tmp/cv2_commit_candidate`. Boundary: generated `s2` now moves past the
old `Dir.glob` MIR shape and GC raw-callback SIGBUS, then fails in full-prelude
smoke on `private DIGITS_DOWNCASE = ...` from `src/stdlib/int.cr`. A hostile
diagnostic showed generated `s2` parses uppercase assignments as ordinary
identifier assignments; treating them as constants exposes a deeper deferred
constant/lower_main frontier. Do not paper over this with a broad visibility
allowlist; fix the parser/constant-lowering root.

Stage2 no-prelude LLVM smoke checkpoint (2026-04-29): generated `s2b` now
passes the no-prelude interpolation smoke. Three backend roots were fixed in
sequence. First, MIR stack `Alloc` slots were emitted by the entry alloca
prepass and then re-hoisted from buffered block IR; the block-IR splitter now
skips alloca names already emitted by the entry prepass. Second, derived LLVM
temporary names used `name.lstrip('%')`, which can produce invalid digit-leading
names such as `%0.conv1`; string interpolation now uses a local-name helper
that strips one leading `%` and prefixes numeric bases. Third, generated s2
discovered string constants during function emission but lost them before tail
constant emission through Hash-backed bookkeeping; string constants now use
parallel arrays as the authoritative ordered table, with the Hash retained only
as a cache. Evidence: `crystal build src/adamas.cr -o
/private/tmp/cv2_string_table_arrays --error-trace`;
`regression_tests/p2_no_prelude_unique_alloca_names.sh
/private/tmp/cv2_string_table_arrays`;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/private/tmp/cv2_string_table_arrays`;
`regression_tests/p2_pending_budget_no_prelude.sh
/private/tmp/cv2_string_table_arrays`; and
`BOOTSTRAP_STAGE_OUT=/private/tmp/cv2_bs_s2_string_table_arrays
BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out
/private/tmp/cv2_bs_s2_string_table_arrays`, which builds `cv2_s2` in ~235s
and reports `smoke no-prelude: ok`. Boundary: full-prelude stage2 smoke still
fails with SIGBUS immediately after `prelude exists`; that is the next
bootstrap frontier.

Proc#call backend-boundary checkpoint (2026-04-29): HIR intentionally emits
`Proc#call` as a plain `Call` so MIR can lower heap Proc dispatch through
`call_heap_proc`, but `lower_missing_call_targets` was also treating that name
as source demand. This was a wrong boundary even in a tiny no-prelude reducer:
`p = ->(x : Int32) { x + 1 }; p.call(41)` left `Proc#call` in the HIR and
also queued it as a missing source function. `Proc#call`, `Proc#call$...`, and
`Proc#call(...)` are now classified with the other backend-owned HIR call
names. Evidence: `crystal build src/adamas.cr -o
/private/tmp/cv2_proc_call_boundary --error-trace`;
`regression_tests/p2_proc_call_backend_boundary_no_prelude.sh
/private/tmp/cv2_proc_call_boundary`;
`regression_tests/p2_backend_intrinsic_boundary_no_prelude.sh
/private/tmp/cv2_proc_call_boundary`;
`regression_tests/p2_pending_budget_no_prelude.sh
/private/tmp/cv2_proc_call_boundary`; and
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/private/tmp/cv2_proc_call_boundary`. Boundary: this is not the remaining
full-source fanout root. A fresh `STOP_AFTER_HIR` profile on `src/adamas.cr`
still reports `lower_missing: 615 -> 35892 (+35277) in 166338.1ms`; the next
root-cause corridor remains supply-driven `Hash` / `Array` / `Hash::Entry`
materialization, not `Proc#call`.

Visibility modifier semantics checkpoint (2026-04-29): top-level collection
and HIR member unwrapping now validate `VisibilityModifierNode` before
discarding the wrapper. This aligns the non-accessor declaration cases with
Crystal's top-level visitor for the covered forms: `private` type/constant/macro
wrappers remain valid, `protected` type/constant/macro wrappers now fail with
the original-style diagnostics, and invalid non-call expressions such as
`private 1` no longer compile silently. Evidence: `crystal build
src/adamas.cr -o /private/tmp/cv2_visibility_modifier_semantics
--error-trace`; `regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
/private/tmp/cv2_visibility_modifier_semantics`;
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/private/tmp/cv2_visibility_modifier_semantics`;
`regression_tests/p2_visibility_protected_namespace_no_prelude.sh
/private/tmp/cv2_visibility_modifier_semantics`; `crystal spec
spec/parser/parser_visibility_spec.cr --error-trace`;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/private/tmp/cv2_visibility_modifier_semantics`; and
`regression_tests/p2_named_tuple_annotation_keys_no_prelude.sh
/private/tmp/cv2_visibility_modifier_semantics`. Boundary: visibility-wrapped
`CallNode` remains allowed as a macro-call escape hatch (`private record`,
typed macro calls) until v2 has a reliable expanded/unexpanded macro-call
marker equivalent to original Crystal's MainVisitor check.

Union annotation + protected namespace checkpoint (2026-04-29): stage2
`STOP_AFTER_HIR` now gets past the former
`debug_cli_root_block_state(...AstArena...)` stub/miss and the subsequent
`protected method 'entries_size' called for Hash(...)` failure. The root fixes
are: registration resolves annotations in the method owner's namespace
(`Frontend::ArenaLike` inside `CLI` resolves to the frontend alias), union
descriptors keep their union-shaped mangled names instead of collapsing through
`resolve_type_alias_chain`, union alias strings are resolved structurally per
variant, union cache hits reject stale non-union descriptors, and protected
visibility now mirrors Crystal's `has_protected_access_to?` rule by allowing
same top namespace/nested types such as `Hash::KeyIterator -> Hash` without
whitelisting `entries_size`. Evidence: `crystal build src/adamas.cr -o
/private/tmp/cv2_protected_namespace --error-trace`;
`regression_tests/p2_visibility_protected_namespace_no_prelude.sh
/private/tmp/cv2_protected_namespace`;
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/private/tmp/cv2_protected_namespace`; `ADAMAS_STOP_AFTER_HIR=1
ADAMAS_PHASE_STATS=1 scripts/run_safe.sh /private/tmp/cv2_protected_namespace
180 4096 src/adamas.cr -o /private/tmp/cv2_protected_namespace_s2` exits 0
after ~145s. Boundary: this unblocks HIR completion but does not solve the
remaining `lower_missing` fanout (`615 -> 35882`, ~159s), which is the next
demand-driven root-cause corridor.

Visibility accessor checkpoint (2026-04-29): parser/HIR now preserve
`private`/`protected` on accessor macros instead of dropping the modifier at
`private getter` / `protected property` parse time. Accessor nodes carry
visibility through LSP AST cache, generated accessor registrations mirror it
into HIR method metadata, and both normal call lowering and property-style
member access reject explicit non-self calls to private accessors. Evidence:
`crystal spec spec/parser/parser_visibility_spec.cr --error-trace`,
`crystal build src/adamas.cr -o /private/tmp/cv2_visibility --error-trace`,
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/private/tmp/cv2_visibility`, and `bash -n
regression_tests/p2_visibility_private_accessor_no_prelude.sh`. Boundary:
broader top-level visibility semantics for constants/types/macros are not yet
fully aligned with original Crystal's top-level visitor.

LLVM value-lookup iterator checkpoint (2026-04-29): after removing the
debug-cache tuple key, generated `cv2_s2` reached LLVM emission for the
no-prelude smoke and crashed inside `LLVMIRGenerator#value_ref(UInt32)` from
`emit_extern_call`. The first bounded attempt only replaced
`@current_func_params.any? { |p| p.index == id }`, which moved the crash into
`find_def_inst` at `block.instructions.find { |inst| inst.id == id }`. The
root pattern is the same: this backend materialization path does not need
closure/Enumerable helpers, and generated stage2 is still fragile around block
iterator helpers in this hot lookup corridor. The fix uses direct while loops
for both parameter-index lookup and definition lookup. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_value_ref_def_loop --error-trace`;
`p2_bootstrap_semantic_emit_oracle.sh`, `p2_pending_budget_no_prelude.sh`,
`p2_universal_helper_fanout_no_prelude.sh`, and `p1_ir_shape_check.sh` pass
with `/tmp/cv2_value_ref_def_loop`; canonical `s1 -> s2` still builds `cv2_s2`
in about 229s. Boundary: generated `cv2_s2` smoke still fails, but ASLR-enabled
LLDB now stops later in `File.new_internal -> File.open -> CLI#file_sha256`,
not in `LLVMIRGenerator#value_ref` or `find_def_inst`.

Debug line-scope cache checkpoint (2026-04-29): the generated `cv2_s2`
no-prelude smoke no longer crashes in `__adamas_string_eq` through
`Hash(Tuple(String, Int32), UInt32)#fetch ->
HIRToMIRLowering#hir_innermost_scope_for_source_line`. The root was a
compiler-internal MIR debug cache using `{loc.path, loc.line}` tuple keys in
self-hosted stage2, where tuple-key Hash lookup can hand invalid String fields
to `Tuple#==`. The fix changes the cache to `Hash(String, Hash(Int32, UInt32))`
and reinitializes the per-function scope caches instead of mutating them with
`clear`, preserving the local stage2 invariant already used for other lowering
maps. Evidence: `crystal build src/adamas.cr -o /tmp/cv2_scope_cache_nested
--error-trace`; `p2_class_method_nested_yield_block_param_no_prelude.sh`,
`p2_loop_block_proc_capture_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, and `p2_pending_budget_no_prelude.sh`
all pass with `/tmp/cv2_scope_cache_nested`; canonical `s1 -> s2` still builds
`cv2_s2` in about 227s. Boundary: generated `cv2_s2` smoke still fails, but
LLDB now stops later in `Crystal::MIR::LLVMIRGenerator#value_ref(UInt32)` from
`emit_extern_call`, not in the old debug-cache `string_eq` path.

Class-method nested-yield block-param checkpoint (2026-04-29): the current
root after the loop-capture fix was not `Pointer#read` itself. `File.open`'s
lowered HIR already creates a concrete `File` and yields it, but the AST-level
`block_param_types_for_call -> infer_yield_param_types_from_body` path inferred
the callsite block using the caller's `@current_class` whenever the callee was
a class method with no instance receiver. For bodies shaped like
`File.open { open_internal { |file| yield file } }`, the nested
`open_internal` block-param inference therefore lost the callee owner context
and the outer user block proc kept `file` as `Pointer`. The fix uses the callee
owner recovered from the function name (`owner_override`) as `self_type_name`
before falling back to `@current_class`. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_yield_owner_fix --error-trace`,
the focused `File.open` HIR reducer now emits `%file : File` and
`File#read(Slice(UInt8))` both inline and in `__crystal_block_proc_0`,
`regression_tests/p2_class_method_nested_yield_block_param_no_prelude.sh
/tmp/cv2_yield_owner_fix` guards the no-prelude class-method nested-yield
shape, and canonical `s1 -> s2` still builds `cv2_s2` in about 230s. Generated
`cv2_s2.ll` now contains `__crystal_block_proc_720 -> File#read(Slice(UInt8))`,
not `Pointer#read`. New frontier: generated `cv2_s2` smoke no-prelude segfaults
after `lower_main: exprs=5`; LLDB shows `EXC_BAD_ACCESS` in
`__adamas_string_eq` called from
`Tuple(String, Int32)#== -> Hash(Tuple(String, Int32), UInt32)#fetch ->
HIRToMIRLowering#hir_innermost_scope_for_source_line ->
propagate_debug_local_bindings -> lower_function_body`. This is a debug-scope
hash/string equality crash, separate from the now-resolved `File.open` block
param precision bug.

Loop block-proc capture checkpoint (2026-04-29): generated stage2 still builds
successfully, and the previous `file_sha256` smoke abort no longer resolves
`file.read(buffer)` to the unrelated
`Hash(String, Array(Tuple(String, Crystal::MIR::Function)))#read(Slice(UInt8))`.
Two root invariants were missing. First, `collect_proc_body_ident_walk` and
`detect_written_captures_walk` did not traverse `LoopNode` and several related
control-flow/container nodes, so a block body shaped as `loop do ... end` could
report `refs=` / `captures=` even when it read and wrote outer locals such as
`buffer` and `hash`. Second, `lower_block_to_block_id` defaulted untyped block
params from `VOID` to `POINTER`, but `lower_block_to_proc` kept the same
untyped param as `VOID`, so a standalone block proc could erase its runtime
receiver parameter even though the inline block view had a pointer-shaped
param. The fix expands the capture walkers and keeps standalone block-proc
param defaulting in parity with inline block lowering. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_loop_capture_walk3 --error-trace`,
`regression_tests/p2_loop_block_proc_capture_no_prelude.sh
/tmp/cv2_loop_capture_walk3`,
`regression_tests/p2_abstract_getter_vdispatch_no_prelude.sh
/tmp/cv2_loop_capture_walk3`,
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_loop_capture_walk3`, and canonical `s1 -> s2` building `cv2_s2` in
about 215s under the 300s/4GB gate. New frontier: generated `cv2_s2`
no-prelude smoke aborts at `STUB CALLED: Pointer$Hread$$Slice$LUInt8$R` from
`__crystal_block_proc_720 -> File.open -> CLI#file_sha256`; this is now a more
precise block parameter type problem (the proc param is pointer-shaped, but not
yet resolved to the concrete `File`/`IO::FileDescriptor` read implementation).

Abstract generated-getter vdispatch checkpoint (2026-04-29): generated stage2
still builds successfully, and the previous smoke abort at
`STUB CALLED: Adamas$CCCompiler$CCFrontend$CCNode$Hspan` is resolved. The
root was not `Node#span` itself: concrete getter/property accessors such as
`LiteralNode#span` are registered in `@function_types` but have no `DefNode`
until generated on demand. `lower_function_if_needed_impl` previously ran
inherited lookup first, so an exact concrete request could resolve back to the
abstract parent `Node#span`, leaving `maybe_generate_accessor_for_name` no
chance to materialize the concrete accessor. The fix preempts inherited lookup
only for registered generated-accessor requests with no `DefNode`, then emits
the real concrete getter body. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_abstract_getter_fix --error-trace`,
`regression_tests/p2_abstract_getter_vdispatch_no_prelude.sh
/tmp/cv2_abstract_getter_fix`,
`regression_tests/abstract_class_method_dispatch_synth.sh
/tmp/cv2_abstract_getter_fix`, `regression_tests/complex/test_vdispatch_struct_return.cr`
compiled and run through `scripts/run_safe.sh`, the fast p2 bootstrap semantic
oracles, and canonical `s1 -> s2` building `cv2_s2` under the 300s/4GB gate.
New frontier: generated `cv2_s2` smoke no-prelude now reaches LLVM emission
and aborts later at
`STUB CALLED: Hash$LString$C$_Array$LTuple$LString$C$_Crystal$CCMIR$CCFunction$R$R$R$Hread$$Slice$LUInt8$R`
from `Adamas::Compiler::CLI#file_sha256 -> compile_llvm_ir`.

Call-argument known-emitted-type checkpoint (2026-04-29): generated stage2
now builds successfully. The immediate `llc` frontier after the return-type
force-lower fix was an invalid call-argument adaptation:
`%eq_ptr_to_fp.* = ptrtoint ptr %r685 to i64` even though `%r685` had already
been emitted as `double`. The root was that the call formatter trusted an old
`find_def_inst(a).type == ptr` hint after `value_ref(a)` had produced an SSA
value with a newer `@emitted_value_types` entry. The fix preserves the packed
scalar decode path, but only when the known emitted SSA type is actually `ptr`
or when there is no emitted-type fact and the older definition type is still
the only available evidence. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_arg_fp_known_type --error-trace`, fast p1/p2 guards, and canonical
`BOOTSTRAP_CHAIN_STAGES=2 ... scripts/build_bootstrap_stages.sh --stages 2`
all passed through the previous LLVM verifier/llc error. The new current
frontier after this checkpoint was generated `s2` smoke aborting immediately
in parser setup with `STUB CALLED: Adamas$CCCompiler$CCFrontend$CCNode$Hspan`;
that follow-up is resolved by the abstract generated-getter vdispatch
checkpoint above.

Return-type force-lower checkpoint (2026-04-29): call lowering now force-lowers
pending call targets only when the current return type is still `VOID`, a
union that needs exact variant shape, or an unresolved generic placeholder. The
root was that `lower_call` / `lower_member_access` refreshed every pending
target before freezing the call instruction type, even when the call already
had a concrete non-union return type. During self-hosting that bypassed lazy
RTA and recursively materialized thousands of concrete helper bodies from
`force_pending_call_targets_for_return_type`. A too-aggressive first guard
skipped union returns as well and broke the stage1 full-prelude `puts 42` smoke
in `Crystal::System::Dir.current` (`File.info?` union PHI mismatch), so unions
remain force-refreshed. Evidence: full-source `STOP_AFTER_HIR` now reports
`process_pending: 316 -> 588 (+272)` and exits in about 137s instead of the
previous `process_pending +14225` / about 234s; canonical `s1 -> s2` no longer
times out and reached `llc` after about 166s. Boundary: `lower_missing` still
materializes about 35k functions; the resulting `ptrtoint`/`double` LLVM
frontier is resolved by the call-argument known-emitted-type checkpoint above.

Nested generic namespace checkpoint (2026-04-29): method/overload lookup now
strips generic arguments per namespace segment instead of truncating the owner
at the first `(`. The root was that owners like
`Indexable(T)::ItemIterator(Array(String), String)` were normalized to
`Indexable`, so `ItemIterator#each` could reuse `Indexable#each` and generate
bogus demand such as `ItemIterator(ItemIterator(...)).new`. Constructor
inference for generic classes under generic namespaces now resolves template
bases such as `Indexable::IndexIterator` and specializes `.new(self)` from the
receiver argument. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_method_index_path3 --error-trace`,
`p2_nested_generic_new_inference.sh`, the fast p2 no-prelude guards, and
`p1_ir_shape_check.sh` passed; full-source `STOP_AFTER_HIR` exits 0 after
about 234s. Boundary: this is a correctness/root fix, not the final demand
pruning fix. The full-source sweep still reports
`lower_missing: 17423 -> 50628 (+33205)`, dominated by concrete-call demand
families (`IO#<<`, `Hash/Array/Indexable`, `Proc#call`, formatting helpers).
Next root remains shrinking `lower_missing.initial` without heuristic depth
limits.

Backend-intrinsic / vdispatch compaction checkpoint (2026-04-29): generated
stage2 now reaches the full-source `STOP_AFTER_HIR` gate with the current
compiler-built `s1`, and backend-owned helper calls no longer masquerade as
missing HIR source demand. The root boundary is that HIR emits some helper
operations as normal `Call` instructions (`__adamas_string_eq`,
`__adamas_hash_get_entry_ptr`, `__adamas_hash_entry_deleted`,
`__adamas_select_ptr`), but MIR/LLVM owns their implementation through
`extern_call` emission / runtime helper definitions. `lower_missing_call_targets`,
`remember_callsite_arg_types`, and `lower_function_if_needed_impl` now skip
that exact allowlist instead of recording them as source-level callees. A fast
no-prelude guard keeps the calls visible in HIR while rejecting their appearance
in missing-target logs. The same checkpoint compacts class vdispatch wrappers
by sharing identical inherited implementation blocks across many runtime type
IDs; union dispatch and dispatch-class-specialized cases remain unshared. It
also explicitly initializes closure by-reference state in `AstToHir#initialize`
because generated stage2 can still miss inline-default ivar initialization for
those sets. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_intrinsic_boundary_check --error-trace`,
`p2_backend_intrinsic_boundary_no_prelude.sh`, `p2_pending_budget_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, `p2_each_index_block_param_no_prelude.sh`,
and fresh generated `s1` `STOP_AFTER_HIR` full-source run all passed; the
missing summary no longer contains the backend-owned intrinsic names. Boundary:
canonical `s1 -> s2` still times out at 300s after `[ALLOC_FLUSH] Generated 98
deferred allocators`, producing only a partial `cv2_s2.ll` (~3.7MB in this run).
Follow-up phase splitting shows the visible timeout is downstream of HIR volume,
not allocator flush itself: full-source `STOP_AFTER_HIR` with
`ADAMAS_PHASE_STATS=1` reports `lower_missing.initial: 17836 -> 43126
(+25290) in 144271.9ms`, while stale-call repair, receiver repair, deferred
allocators, and final fixed-point missing together add only about 400 functions
and about 11s. `ADAMAS_STOP_AFTER_MIR=1` still times out at 300s while
lowering `Body 20001/35221`, so the next root is the concrete-call demand
volume created by the initial missing-target sweep; MIR/allocator symptoms are
secondary until that reachable HIR set shrinks.

Macro diagnostic JSON checkpoint (2026-04-29): one confirmed supply leak was
`src/compiler/semantic/macro_expander.cr` importing `json` only for env-gated
macro-body diagnostics and using `Hash#to_json` inside diagnostic branches. HIR
lowers whole method bodies, so the runtime-disabled branches still pulled
generic `Array/Hash/Set#to_json` and `JSON::Builder` into the compiler's own
demand graph. The fix removes the `json` require from `MacroExpander` and uses
a scalar-only `MacroDiagJson` JSONL writer. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_macro_json_free --error-trace`,
`p2_pending_budget_no_prelude.sh` -> `total=40 lower_missing_delta=0`,
`p2_bootstrap_semantic_emit_oracle.sh`,
`p2_backend_intrinsic_boundary_no_prelude.sh`, and
`p2_each_index_block_param_no_prelude.sh` all passed. Full-source
`STOP_AFTER_HIR` improves modestly (`42859` functions, exit ~201s), and the
fresh missing summary no longer shows `JSON::Builder`/generic `to_json` in the
top suppliers. Boundary: this is a real root fix for diagnostic JSON demand,
not the final `lower_missing.initial` fix; the next supplier is now dominated
by virtual/abstract calls such as `IO#<<`, `Proc#call`, hash key helpers, and
formatting/object-id corridors.

Static truthiness checkpoint (2026-04-29): HIR branch lowering now prunes
branch bodies whose condition has already lowered to a constant truthiness
value, including RHS branches of short-circuit conditions. The root was that
`responds_to?` can lower to a Bool literal after expression lowering while
`lower_if` still materialized both pre-created body blocks; dead calls such as
`Int32#object_id` then entered `lower_missing_call_targets` as concrete source
demand. The fix preserves condition side effects, converts constant condition
branches to jumps, and for no-`elsif` `if` expressions lowers only the CFG
reachable body after condition lowering. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_static_truthy_if --error-trace`,
`p2_static_truthy_dead_branch_no_prelude.sh`, `p2_pending_budget_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, `p2_backend_intrinsic_boundary_no_prelude.sh`,
`p2_each_index_block_param_no_prelude.sh`, and `p1_ir_shape_check.sh` passed.
Full-source `STOP_AFTER_HIR` remains green and improves only modestly
(`lower_missing: 17404 -> 42732 (+25328)`), so this is a real root fix for
static dead-branch demand but not the final Hash/object-id corridor fix. The
next frontier is the remaining `Hash#entry_matches?` / union call-shape demand
that still produces value-type `object_id` missing targets.

Object-id responds_to checkpoint (2026-04-29): `responds_to?(:object_id)` now
uses the Crystal ownership rule for `object_id` (Reference and descendants)
instead of trusting the mutable function registry. The root was circular
pollution: once a bogus value-type `UInt32#object_id` / `Tuple#object_id`
specialization had been admitted anywhere in the run, later `responds_to?`
queries could see that synthetic function base and lower to `true`. The fix
answers the `object_id` predicate from the class parent chain and keeps value
types (`UInt32`, `Tuple`, `Int32`, etc.) false while preserving reference types
such as `String`. Evidence: `p2_object_id_responds_to_semantics.sh`, the same
fast p2 guards, `p1_ir_shape_check.sh`, and full-source `STOP_AFTER_HIR` all
passed. Boundary: this removes value-type `object_id` from the top missing
summary but does not materially shrink `lower_missing` (`+25329`), so the next
bootstrap root is still the broader initial missing-target demand volume
(`Indexable#new`, `Proc#call`, value initializers, debug helpers).

Macro control checkpoint (2026-04-29): full-prelude Kqueue HIR no longer
registers both sides of the Darwin `LibC.has_constant?(:EVFILT_USER)` macro
inside `Crystal::EventLoop::Kqueue#after_fork`. The root was registration
ordering for module macro literals: `process_macro_literal_in_module` stripped
`{% if %}` / `{% else %}` control lines before `expand_flag_macro_text` could
choose a platform branch, so the fallback pipe body was parsed and registered
with the EVFILT_USER body. The fix expands platform macro controls before
stripping in the raw-text and per-text module literal paths, keeps the class
literal path on the centralized `register_class_members_from_expansion`
walker, and synchronizes semantic/HIR platform `LibC.has_constant?` fallbacks
for the currently modeled constants. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_macro_control_check --error-trace`,
`regression_tests/p2_macro_control_module_literal_guard.sh
/tmp/cv2_macro_control_check`, `p2_bootstrap_semantic_emit_oracle.sh`, and
`p2_pending_budget_no_prelude.sh` passed; the generated-stage2 no-prelude
guard remains at `frontier=nocodegen_clean_full_codegen_hang`. The new guard extracts
`Kqueue#after_fork` HIR and requires `LibC.@@EVFILT_USER` while rejecting
`Crystal::System::FileDescriptor.system_pipe` / `LibC.@@EVFILT_READ` inside
that function.

Shape-oracle maintenance checkpoint (2026-04-29):
`p2_selfhost_stage2_shape_guard.sh` is green again after making two historical
callback-shape sentinels demand-aware. `Array(String)#each_index` and
`Dir.glob(..._block_splat)` are still checked when their nested proc wrappers
are materialized, but their absence is no longer a failure because recent
demand/RTA and macro-control fixes removed the old incidental materialization
paths. The `each_index` root invariant now has a direct fast no-prelude guard:
`p2_each_index_block_param_no_prelude.sh` forces `["x"].each_index { |i| i }`
and requires an Int32-shaped block proc in HIR. Evidence:
`p2_each_index_block_param_no_prelude.sh /tmp/cv2_shape_guard_check` and
`p2_selfhost_stage2_shape_guard.sh /tmp/cv2_shape_guard_check` passed.

Getter/proc-shape checkpoint (2026-04-29): `of -> Nil` type annotations now
stringify as `Proc(Void)` so registration-time inference for
`Process.after_fork_child_callbacks` does not seed `Array(String)` and later
lower `String#call`. Generic container canonicalization preserves full
`Proc(...)` parameter shapes, and array element typing prefers the value's own
Array descriptor when the lowering context map is stale. Getter field inlining
is now proof-based: only a source method whose body is the trivial `@ivar`
getter can inline as `FieldGet`; methods sharing an ivar name but having side
effects (for example `Function#next_value_id`) stay as calls. The getter proof
also treats out-of-arena body ExprIds as "not proven getter" instead of raising.
Evidence: `crystal build src/adamas.cr -o /tmp/cv2_safe_commit
--error-trace`, `p2_bootstrap_semantic_emit_oracle.sh`,
`p2_pending_budget_no_prelude.sh`, and
`p2_generated_stage2_no_prelude_puts_guard.sh` all passed. The generated-stage2
guard now fails closed on any unrecorded `STUB CALLED` before accepting the
current full-codegen frontier.

Cross-block slot checkpoint (2026-04-29): generated stage2 no longer emits
malformed empty-slot LLVM for the no-prelude `puts 7` smoke. The root was the
LLVM backend consuming `@cross_block_slots` via `hash[key]?` inside an
assignment-in-condition; generated stage2 could enter the branch for a missing
slot and bind an empty local string, producing `store ptr null, ptr %`. The
backend now gates slot consumption by `has_key?` before indexing. Falsifier:
an attempted `Hash#clear` real-function override made generated `Hash#clear`
bodies layout-safe but did not remove the malformed `%`, so stale Hash storage
was not the root. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_slot_haskey_only --error-trace`,
`p2_bootstrap_semantic_emit_oracle.sh`, `p2_pending_budget_no_prelude.sh`,
`bash -n regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh`,
`git diff --check`, and
`p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_slot_haskey_only` ->
`frontier=extern_puts_arg_type_codegen_gap`. The next root is extern-call
argument typing in generated stage2: the emitted IR calls
`__adamas_print_int32_ln(ptr null)` instead of `i32 7`.

Extern arg type checkpoint (2026-04-29): generated stage2 now emits a single
no-prelude `puts 7` extern call with the correct scalar ABI shape:
`call void @__adamas_print_int32_ln(i32 7)`. The root had two backend
pieces. MIR block ordering used `Set(HIR::BlockId)`; generated stage2
mis-deduped a one-block function and lowered the entry block twice, so the
ordering pass now uses a small linear visited list. LLVM extern-call argument
typing then read `@value_types[arg_id]?` with a pointer fallback; generated
stage2 could miss the present Int32 entry and print `ptr 7`, so extern-call
arg typing and called-function signature tracking now gate by `has_key?` before
indexing. The same key-presence invariant was applied to `value_ref` lookups
for constants, cross-block slots, and emitted value names. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_extern_arg_type_fix --error-trace`,
`git diff --check`, `bash -n
regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh`,
`p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_extern_arg_type_fix` ->
`frontier=nocodegen_clean_full_codegen_hang`, raw IR inspection of the kept
tmp artifact shows `i32 7`, and the fast p2 semantic/pending oracles pass. The
next root is no longer no-prelude extern-call ABI; it is the full-codegen-only
frontier where `--no-codegen` exits cleanly but the full path does not produce
the executable.

Observed but not landed (2026-04-29): `SystemError#included` expands to a
`BeginNode` containing `extend ::SystemError::ClassMethods`; processing that
`BeginNode` would expose the right root for `RuntimeError.from_errno` stubs, but
the naive recursive expansion branch currently reintroduces a long stage2
`lower_main` timeout. Revisit as a separate CAUTION change with a no-prelude
oracle before landing.

Dirty review note (2026-04-28): the in-progress `Union(*T)` / `StaticArray`
annotation substitution fix is currently verified only for the narrow
`Tuple(Char)#to_static_array` null-buffer corridor. Hostile adversary repros
with real multi-element and nested tuples (`{1, 'a', true}.to_static_array`,
`{{1, 'b'}, 2}.to_static_array`) no longer hit the original null allocation
shape, but still expose a separate StaticArray-of-Union load/unwrap boundary:
direct equality prints false and explicit `as(Int32)` returns the union
type-id-like value (`5`) instead of the payload. Do not claim full
`Tuple#to_static_array` correctness until StaticArray(Union(...), N)
store/load plus union unwrap semantics are covered by a run-safe regression.

Hostile review note (2026-04-28): packed splat call-site types must be consumed
by `lower_def` before named/default parameters after `*args` are assigned.
Otherwise a signature like `buffered(message, *args, exception = nil)` can type
`exception` as the packed splat tuple and supply-drive bogus
`Tuple/Array#inspect_with_backtrace` targets. Covered by
`regression_tests/named_arg_after_splat_type_alignment.sh`.

Dead nil branch checkpoint (2026-04-28): wrappers with `exception = nil` used
to emit dead `Nil#inspect_with_backtrace` in unreachable `if exception`
branches because `lower_if` only learned the constant false condition after
lowering the condition to a Bool literal, after both branches had already been
lowered. `static_nil_condition_value` now treats a bare local whose current HIR
type is exactly `Nil` as statically false. Covered by
`regression_tests/dead_nil_branch_after_splat_repro.sh`. This is a correctness
and demand-source fix, but not the main `lower_missing` growth fix.

RTA root virtual replay checkpoint (2026-04-28): method-part RTA now requires a
live owner to declare or inherit the called instance method before replaying a
virtual target to that owner. This preserves `Exception` subclass overrides for
root-typed calls such as `exception : Object; exception.inspect_with_backtrace`,
but avoids materializing unrelated live owners that cannot answer the method.
Covered by `regression_tests/rta_root_virtual_method_replay_guard.sh`.

Direct `s1 -> s2` previously produced a stage2 compiler in the focused gate:

```bash
crystal build src/adamas.cr -o /tmp/cv2_hir_emit_stop --error-trace
ADAMAS_PHASE_STATS=1 \
  scripts/run_safe.sh /tmp/cv2_hir_emit_stop 300 4096 \
    src/adamas.cr -o /tmp/cv2_s2_hir_emit_stop
```

Verified signal: `[EXIT: 0] after ~265s`, produced `/tmp/cv2_s2_hir_emit_stop`.

Current canonical wrapper checkpoint (2026-04-28): `scripts/build_bootstrap_stages.sh`
needed a Bash 3.2 / `set -u` fix for empty `CHAIN_ARGS`; after that fix the
wrapper reaches the real stage2 build. With `--stages 2`, 300s, and 4096MB,
stage1 builds and both smokes pass, but stage2 times out after writing a 189MB
`cv2_s2.ll` (3,930,328 lines, 39,112 LLVM `define`s, 338 stub markers) and
after `[ALLOC_FLUSH] Generated 98 deferred allocators`. Treat the old direct
success as stale for the canonical bootstrap gate until the IR over-materialized
helper graph is reduced.

AST demand-filter checkpoint (2026-04-28): the default AST reachability path is
still conservative/all-defs unless `ADAMAS_AST_FILTER_DEMAND=1` is set.
The opt-in demand scanner now walks packed `main_exprs`, builds a method-name
worklist, gates candidate owners by constructed/always-reachable types, and
feeds the existing AST filter. It is a diagnostic scaffold, not the default
bootstrap fix. Evidence on a full `src/adamas.cr` `STOP_AFTER_HIR` run:
`process_pending` drops from `+14371` to `+4148`, but `lower_missing` grows
from `+25702` to `+35210`, leaving total HIR functions nearly unchanged
(`43471` -> `43091`). `DEBUG_MISSING_SUMMARY=1` shows the compensating demand
comes from concrete calls already emitted into HIR (`IO#<<`,
`__adamas_string_eq`, `Array#root_buffer`, `Hash` internals,
`JSON::Builder`, and `Hash::Entry#inspect/to_s`). Next root work is therefore
to prevent dead/unneeded serialization/formatting/hash bodies from entering HIR
before `lower_missing`, not to filter concrete missing calls blindly. Guard:
`regression_tests/p2_ast_filter_demand_no_prelude.sh`.

LLVM reachability checkpoint (2026-04-28): backend function reachability is now
available only under `ADAMAS_LLVM_REACHABILITY=1`; the default remains the
previous emit-all behavior. On the full compiler, opt-in backend RTA prunes
`9959` MIR functions (`37792` total -> `27833` emitted) and reduces the
progress-run `.ll` artifact from the previous `189MB` shape to `146MB`, but
the 300s gate still times out later in LLVM finalization/undefined-extern
declaration emission. This is a useful lever, not a complete bootstrap fix.
Guard: `regression_tests/p2_llvm_reachability_no_prelude.sh`.

Fast stage2 HIR emit also passes:

```bash
regression_tests/p2_selfhost_hir_emit_no_prelude.sh /tmp/cv2_s2_hir_emit_stop
```

Verified signal: `p2_selfhost_hir_emit_no_prelude_ok`.

The full wrapper gate now reaches the generated stage2 compiler, then stops on
the generated-compiler smoke:

```bash
BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2 \
BOOTSTRAP_CHAIN_STAGES=2 \
BOOTSTRAP_TIMEOUT_SEC=300 \
BOOTSTRAP_MEM_MB=4096 \
  scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2
```

Current signal after the latest generated-stage2 guard pass: stage1 build and
generated `s2b` build still pass, and the generated-stage2 no-prelude `puts 7`
guard now moves past the old `IO::FileDescriptor#system_pos`,
`Crystal::System::Kqueue.set`, and `File#file_descriptor_close` recursion
frontiers. The accepted guard signal is:

```bash
regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_inherited_owner
```

Verified signal: `p2_generated_stage2_no_prelude_puts_guard_ok
frontier=nocodegen_clean_full_codegen_hang` after `f8313232` cleared the
prior `eventloop_after_fork_rta_gap`. Root cause was not the abstract-base
RTA discovery itself — Polling/Kqueue#after_fork were correctly recorded
in `@rta_called_method_parts` and pushed onto `@pending_function_queue`
by `undefer_rta_functions`. The bug was that
`force_lower_function_for_return_type` mutated the same queue via
`Array#delete(name)` while `process_pending_lower_functions` was iterating
it by index; the delete shifted later entries down, skipping the
undefer-pushed virtual subtypes past the loop's current `idx`. Fix:
drop the queue mutation; existing `has_function_with_body?` /
`function_state.completed?` guards make stale entries safe. The next
recorded frontier is the `--no-codegen` clean exit while full-codegen
still hangs in `Crystal::RWLock#write_lock` reached from `Process.fork`,
tracked separately.

The previous `String contains null byte` frontier was resolved as a div/rem
signedness bug in `llvm_backend`, not a `String#byte_index(0)` search bug.
`CLI` builds `pipeline_hash_str = pipeline_hash.to_s(16)` from a `UInt64` FNV
hash; `Int#to_s(base)` calls `num.remainder(base).abs`; the backend selected
`srem` because it OR-ed operand signedness, which turns high-bit unsigned
values into negative remainders and corrupts hex digits into bytes containing
`0x00`. The fix matches original Crystal `primitives.cr:149`
(`t1.signed? ? srem : urem`): div/rem signedness now follows the dividend
only. See LM-499 and `regression_tests/p2_u64_to_s_base16_no_null.sh`.

The `check_index_out_of_bounds` ABORT-stub frontier was then cleared by
LM-500 as a lazy-RTA allowlist gap, not a virtual-dispatch or receiver-set
bug. `Indexable#fetch(index : Int, &)` calls the private helper
`check_index_out_of_bounds`, which is never virtually dispatched, so its
method-part carries no concrete receiver in `@rta_virtual_receivers` and
`rta_method_part_matches_owner?` returns false for every live container.
The existing allowlist mechanism
(`internal_container_helper_exact_demand?` /
`internal_container_helper_name_exact_demand?` in `ast_to_hir.cr`) already
carries peers like `unsafe_fetch`, `fetch`, and `increase_capacity`; the fix
adds `check_index_out_of_bounds` to the `Array`, `Slice`, and `Deque` arms
in both functions. Evidence: `generated_s2.ll` now has 78 real
`check_index_out_of_bounds` definitions with 0 `abort_stub` lines; the
nocodegen probe exits clean; zero regression suite delta. See LM-500.

The `Crystal::RWLock#write_lock` corridor noted on LM-499 was then narrowed
to a two-layer root by LM-501. Inline lowering of `Atomic#set` / `Atomic#swap`
in `hir_to_mir.cr` was reading `args[2]` as the stored value, but the Crystal
signature is `swap(value : T, ordering = :seq_cst)`, so `args[2]` is the
`AtomicOrdering` enum and `args[1]` is the value. The writer-lock path
therefore stored `AtomicOrdering::Acquire = 4` into `@writer` instead of
`LOCKED = 1`. The fix pins both inlined ops to `args[1]`; fresh
`write_lock` disassembly now emits `ldr w9, [Crystal$CCRWLock__classvar__LOCKED]`
instead of `mov w9, #0x4`. The puts-guard now carries a positive-shape
regression check for both invariants. See LM-501.

LM-502 then closed the `Process.@@rwlock = null` corridor. The four
class-body / macro-expansion iteration loops in `ast_to_hir.cr` recognised
`when AssignNode` but only registered `ConstantNode` targets; the
Darwin-only `@@rwlock = Crystal::RWLock.new` lives under a `{% else %}`
branch with a `ClassVarNode` target, so it never reached
`@deferred_classvar_inits` and no `__classvar_init__` function was emitted.
A new helper `register_class_assign_from_expansion` now records both
`ConstantNode` and `ClassVarNode` AssignNode targets at all four sites; the
deepest macro-literal inner loop is left untouched (an exploratory addition
there flipped `String::Formatter::HAS_RYU_PRINTF` macro branches and stubbed
`current_char`). Lazy classvar count goes from 20 to 21; fork-test IR now
contains a real `__classvar_init__Crystal$$CCSystem$$CCProcess__rwlock`
calling `Crystal$CCRWLock$Dnew()`. The next generated-stage frontier is the
post-fork child hang in `Crystal::System::Signal.after_fork`'s
`@@pipe.each` block (sample shows `Signal.after_fork + 68`). See LM-502.

Current diagnosis / recently fixed roots:

- Generated-stage2 no-prelude `puts 7` moved through three backend/runtime
  helper frontiers in one root-fix cluster. Same-owner system and class helper
  calls are now recorded as exact RTA demand, so concrete helpers such as
  `IO::FileDescriptor#system_pos` and stage2 class helpers are materialized
  instead of synthesized as abort stubs. Overload matching now treats raw
  `Pointer` values as compatible with typed `Pointer(T)` parameters, which
  lets generated stage2 select the real
  `Crystal::System::Kqueue.set(Pointer(LibC::Kevent), Int32, Pointer(LibC::Kevent), Int32, Timespec*)`
  helper instead of falling through to a stub. The later bus-error frontier
  was an inherited-wrapper root cause: `File#file_descriptor_close` was
  materialized by lowering the ancestor `IO::FileDescriptor` body under
  `@current_class = File`, so implicit calls inside the ancestor body resolved
  back to the child wrapper and recursed. The fix preserves requested wrapper
  owner only for value/primitive/generic specialization cases; normal
  reference-class inherited wrappers lower the resolved ancestor body while
  still materializing the requested symbol for dispatch. HIR evidence after the
  fix: `File#file_descriptor_close` calls
  `IO::FileDescriptor#file_descriptor_close$block`, not itself. Guard evidence:
  `p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_inherited_owner` ->
  `frontier=string_null_byte`. `IO#pos` is now accepted as a valid runtime
  dispatch-helper shape for `IO::FileDescriptor#tell`; reject only aborting
  `tell`/`pos` stubs, not this dispatch helper. The self-host shape guard no
  longer requires a tuple allocation inside `Dir.glob(...block_splat)` because
  the current correct HIR forwards directly to the `Enumerable` overload; it
  now checks the real invariant instead: the forwarding block proc remains
  `String`-shaped and the old `_block_splat` / `String#each$block` regressions
  remain absent.
- Bare receiverless `puts/print/p/pp` no longer fall through the late
  `Object#...` implicit-receiver fallback in `AstToHir#lower_call`. That
  fallback was missing the same builtin exemption already present in the
  earlier self-resolution branches, so fresh generated `s2b` no-prelude
  compiles could drift into receiver-call resolution and die in the helper
  tuple-iteration corridor (`Tuple$Heach$$block`) before the direct runtime
  print fallback had a chance to run. Evidence:
  `regression_tests/stage2_no_prelude_puts_runtime_repro.sh /tmp/cv2_puts_receiverfix`
  -> `not reproduced`;
  `regression_tests/p2_generated_stage2_no_prelude_interp.sh /tmp/cv2_puts_receiverfix`
  -> `p2_generated_stage2_no_prelude_interp_ok`;
  `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_owned_return_fix3`
  -> `p2_generated_stage2_no_prelude_puts_guard_ok frontier=io_filedescriptor_tell`.
  The old generated-stage2 no-prelude `Tuple$Heach$$block` frontier is removed;
  the old synthetic-main MIR blockers (`Missing hash key: __crystal_main` and
  `MIR function stub not found for: __crystal_main`) are removed. Generated
  `s2b` used to reach `STUB CALLED: IO::FileDescriptor#tell`.
- Inherited instance-method materialization now lowers child wrappers as real
  bodies instead of short-circuiting on an already-lowered ancestor target.
  That root-fix removes the generated-stage2 `IO::FileDescriptor#tell` abort
  stub corridor without any LLVM hardcode: plain `File.open { |f| f.tell }`
  HIR now contains only `IO#tell`, `lldb --batch -o 'disassemble -n
  IO$CCFileDescriptor$Htell' /tmp/cv2_tell_fix_s2` shows a real delegate body
  calling `IO$CCFileDescriptor$Hpos`, and
  `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_puts_fix2` now confirms two invariants together: `tell` still
  delegates to `IO::FileDescriptor#pos`, and nilary
  `IO::FileDescriptor#puts` no longer reuses the `puts(String)` body.
  Full self-host MIR emitted by `/tmp/cv2_puts_fix2` now contains
  `func @IO::FileDescriptor#puts(%0: Type#204) -> Nil` with `print(Char '\n')`
  while `func @IO::FileDescriptor#puts$String` stays separate. The old
  generated-stage2 `String#bytesize` crash from newline handling is gone.
  The next generated no-prelude blocker then moved to the HIR/codegen boundary:
  `Array(String)#each$block` materialized its nested `each_index` callback as
  `String ->` because fallback block-param inference treated `each_index` like
  element-yielding `each`. The fix teaches `fallback_block_param_types` that
  `each_index` yields `Int32`; fresh self-host HIR now contains
  `func @__crystal_block_proc_291(%2: 4)` and calls
  `Array(String)#unsafe_fetch$Int32`, not `unsafe_fetch` with a String-shaped
  callback argument. `regression_tests/p2_selfhost_stage2_shape_guard.sh
  /tmp/cv2_emitblock_fix` now checks the `Array(String)#each_index` callback
  shape, and `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_emitblock_fix` reports
  `frontier=hash_each_entry_with_index_null_block`. The next root was a
  two-part HIR/backend issue in
  `Crystal::MIR::LLVMIRGenerator#emit_missing_crystal_function_stubs`: the
  late pass re-walked a temporary `Hash` via `each`/`each_key`, which lowered
  through `Hash#each_entry_with_index` and exposed the still-open nested raw
  block callback ABI; switching that pass to an `Array` snapshot removes the
  artificial Hash iterator. The snapshot must stay flat (`name, return_type,
  arg_count, arg_types`) because nested tuple elements in generated-stage2
  currently still expose aggregate layout bugs. Separately,
  `block_param_types_for_call` did not normalize compiler collection aliases
  such as `Crystal::MIR::Array(T)` before element inference, so
  `Array(T)#each` blocks could be emitted as `Void ->`; the fix reuses
  `normalize_compiler_collection_owner_name` for element/hash block-param
  inference. Fresh self-host HIR now gives the late-emission Array block a
  real `Tuple(String, String, Int32, Crystal::MIR::Array(String))`-shaped
  parameter, not `Void`, and the generated no-prelude `puts 7` frontier moves
  to `STUB CALLED: IO$CCFileDescriptor$Hsystem_pos`.
  The late-emission snapshot must avoid introducing artificial nested tuple
  layouts as a workaround, but nested tuple/aggregate block parameters are a
  real language/runtime invariant: add a separate no-prelude oracle for
  blocks yielding nested tuples/arrays and verify HIR/MIR/LL layout parity
  instead of treating flattening as a general solution. Do not assume only
  shallow tuple payloads: real block-yield values may contain arbitrarily
  nested tuples/arrays/hashes, so the eventual fix must preserve aggregate
  layout recursively instead of special-casing the current flat snapshot.
- Stage2 shape guard now protects four self-host codegen roots in one MIR
  gate (`regression_tests/p2_selfhost_stage2_shape_guard.sh`):
  - stale cache-only call return repair no longer rewrites
    `Slice(UInt8)#[]` from `UInt8` to stale container-shaped returns;
  - bare `return` in nilable functions now materializes a nil union value
    (`String#byte_index(Int32, Int32)` no longer emits bare MIR `ret`);
  - deferred runtime constants update `@constant_types` after real lowering
    (`CRYSTAL_SRC_PATH` now reads as `String`, not `VOID`, avoiding
    `Path | String` variant miswrap);
  - splat parameters are rebound to tuple locals in the method body, so
    `Dir.glob(*patterns, &block)` no longer self-recurses through its
    `_block_splat` wrapper.
  - nested inline-yield fallback no longer emits a call back to the currently
    lowered `_block_splat` wrapper. The fallback now resolves splat/block
    targets through the block-overload table and records the corrected call
    target without eagerly forcing the callee body.
  - scalar splat fallback targets now keep their `_block_splat` wrapper instead
    of being over-corrected to the `Enumerable` overload. This keeps
    `Dir.glob("pattern", &block)` from dispatching `String#each$block` inside
    `Dir.glob$Enumerable...`.
  - `SymbolCollector#@table_stack` is explicitly typed as
    `Array(SymbolTable)`, preventing V2 from widening it to
    `Array(SymbolTable) | Array(String)` and routing `current_table.lookup_macro`
    through `T#lookup_macro`.
  - trivial `NameResolver` zero-arg helpers are no longer required as generated
    compiler call targets; their bodies are inlined at source call sites, moving
    generated no-prelude smoke past the `current_owner_symbol` helper stub
    cluster.
  - `TypeInferenceEngine#guard_watchdog!` now bypasses deferred work-queue
    lowering as a leaf guard, so self-host HIR/MIR contains the helper body
    instead of leaving a concrete call target for LLVM to synthesize as an abort
    stub. A broad stale-Pending requeue was tested and rejected because it
    reopens the deep generic helper fan-out that lazy RTA intentionally prunes.
- Nilable query calls on concrete containers can now materialize inherited
  included-module implementations instead of falling back to the first fuzzy
  overload. This keeps `Array(Nil | Array(ExprId))#[]?$Int32` on the
  `Indexable#[]?` path instead of mis-targeting `#[]?$Range`.
- Semantic compiler cache key hashing no longer calls `.hash` on immediate
  primitive fields (`UInt64`, `Bool`) while self-hosting. The cache keys now
  combine object ids and booleans arithmetically, avoiding the generated
  stage2 `Object#hash` vdispatch corridor.
- `TypeInferenceEngine#primitive_metaclass?` no longer relies on flow narrowing
  across `type.is_a?(PrimitiveType) && type.name...`. It now explicitly casts to
  `PrimitiveType` before calling `#name`, so HIR emits
  `PrimitiveType#name -> String` followed by `String#ends_with?`, not stale
  `Hash(... )#ends_with?`.
- `Hash(String, Nil).new(block, initial_capacity:)` no longer resolves to the
  `default_value : V` overload. Generic overload matching now evaluates
  annotations in the requested concrete owner context, so `V` is `Nil` for
  `Hash(String, Nil)` instead of a wildcard.
- Explicit receiver block calls now keep the concrete generic receiver owner
  when searching block thunks. This removes late generic-module abort stubs such
  as `Indexable(T)#reverse_each$$block`; the self-host HIR trace now lowers
  concrete `Array(...)#reverse_each$block` targets instead.
- Default argument expansion now searches included module chains before final
  target canonicalization. This preserves `Enumerable#each_with_index(offset =
  0, &)` when reached through concrete Array/Slice owners, so zero-arg block
  calls become one-arg calls before block proc lowering.
- Direct LLVM small-Hash linear-scan overrides are disabled. They duplicated
  `Hash::Entry` layout knowledge in the backend and corrupted self-hosted
  `Hash(String, Nil)` / `Hash(String, T)` paths; normal HIR/MIR lowering now
  owns those method bodies.
- Exact-demand helper bodies invalidated by layout repair are requeued and can
  be processed again in the same pending pass. This removed late abort stubs for
  `Array(String)#increase_capacity` and `Array(Crystal::HIR::TypeRef)#to_unsafe`.
- HIR-only emit no longer depends on backend/runtime weak spots:
  - `--emit hir --no-link` stops after writing HIR when MIR/LLVM emit is not
    requested.
  - HIR pretty-printers avoid `Enumerable#join(io, ...)`, which pulled
    `IO::FileDescriptor#tell`.
  - CLI HIR output uses the same `LibC.open` / `LibC.close` pattern as LLVM
    output instead of `File.open` / `IO::FileDescriptor#system_close`.

Remaining risk:

- The current generated stage2 plain smoke times out in prelude loading after
  `prelude exists`. The current generated stage2 no-codegen no-prelude smoke
  times out after `STUB CALLED:
  Adamas::Compiler::Semantic::TypeInferenceEngine#guard_watchdog!`.
  Treat these as the next root-cause targets before any `s3b+` attempt.
- Stage2 still has a separate generic module block corridor around
  `Enumerable(T)#any?$$block`. A no-prelude function-definition HIR emit and a
  full `puts 42` smoke can still hang/abort there under the generated s2
  compiler. A broader implicit-self block receiver experiment was refuted
  because it caused an early `Index out of bounds` in self-host HIR lowering.
- `lower_missing` still grows HIR heavily during full self-compile
  (`17769 -> 43471`, `+25702`, in the latest focused STOP_AFTER_HIR gate). The
  STOP_AFTER_HIR gate exits 0 in ~209s, but the canonical full stage2 build
  still times out at 300s after emitting a 189MB `.ll`; this remains the main
  demand-driven cleanup target before `s2 -> s3`.
- Dominant families are broad fallback helpers on compiler-internal containers:
  `Array#to_s`, `Array#inspect`, `Array#exec_recursive`,
  `Array#object_id`, `Hash#to_s`, `Hash#inspect`,
  `Hash#exec_recursive`, and `Hash::Entry#to_s/#inspect`.
- Current source contexts:
  - `Object#to_s` enqueues `Array#to_s` / `Hash#to_s`
  - `Object#inspect` enqueues `Array#inspect` / `Hash#inspect`
  - `Reference#same?` enqueues `Array#object_id`
  - `Dir::Globber#glob` enqueues some `Hash#each`
- `DEBUG_RTA_KEEP_REASONS=1` shows the active `process_pending` frontier is
  dominated by `keep:exact_called`, not by owner/method-part fallback:
  `Array#to_s`, `Array#object_id`, `Hash#to_s`, `Hash#object_id`,
  `Hash::Entry#to_s`.
- `scripts/timeout_sample_lldb.sh` confirms the time is spent in HIR lowering /
  type-name lookup / string hashing, consistent with excessive admitted wrapper
  volume rather than a single tight runtime loop.

See `LANDMARKS.md` LM-463..LM-475 for detailed evidence and refutations.

## Refuted Fix Branches

Do not retry without new evidence:

- Broad `Object` / `Reference` virtual-target replay gating alone.
- `emit_all_tracked_signatures` universal-method pruning alone.
- Replay gating plus emit pruning combination.
- Defer/enqueue guard for universal helpers on deep generic owners.
- RTA replay-depth guard that prevents speculative replay enqueues from marking
  exact `@rta_called_methods`.
- `rta_method_part_matches_owner?` broad-root helper ancestor filter.
  - No movement on `p2_root_self_replay_no_prelude.sh`: `process_delta=20`,
    `object_replays=28`, `reference_replays=21` unchanged.
- Combined broad-root immediate-replay gate plus broad-root helper RTA filter.
  - Synthetic oracle reduced replay counts (`Object 28->16`, `Reference 21->16`)
    but not `process_delta` or `total`.
  - 120s `STOP_AFTER_HIR` diagnostic still timed out, with queue reaching `40k`
    and the same helper families (`Array#to_json`, `Array#inspect`,
    `Array#to_s`, `Array#exec_recursive`, `Array#hash`, `Hash#...`).
- Replacing `TypeInferenceEngine#guard_watchdog!` calls with direct
  `Frontend::Watchdog.check!` calls.
  - It removes the helper stub but duplicates watchdog lowering at every call
    site and fails the stage2 build envelope before producing `cv2_s2`.
- Changing `guard_watchdog!` visibility from private to public.
  - HIR still contains calls to `guard_watchdog!` but no function body; the
    missing-helper root is not method visibility.

Common lesson: name-family containment can remove individual symptoms but has
not yet removed the underlying broad fallback demand leak.

## Fast Oracles

Run before expensive bootstrap attempts:

```bash
regression_tests/p2_bootstrap_semantic_emit_oracle.sh bin/adamas
regression_tests/p2_selfhost_hir_emit_no_prelude.sh bin/adamas
regression_tests/p2_pending_budget_no_prelude.sh bin/adamas
regression_tests/p2_root_self_replay_no_prelude.sh bin/adamas
regression_tests/p2_universal_helper_fanout_no_prelude.sh bin/adamas
regression_tests/p2_selfhost_stage2_shape_guard.sh bin/adamas
regression_tests/p2_llvm_tail_stats_no_prelude.sh bin/adamas
regression_tests/p2_debug_filter_no_variadic_splat.sh
```

Expected current signals:

- `p2_bootstrap_semantic_emit_oracle_ok`
- `p2_selfhost_hir_emit_no_prelude_ok`
- `p2_pending_budget_no_prelude_ok ... total=103 max_queue=57`
- `p2_root_self_replay_no_prelude_ok process_delta=20 total=47 ...`
- `p2_universal_helper_fanout_no_prelude_ok deep_helpers=0`
- `p2_selfhost_stage2_shape_guard_ok`
- `p2_llvm_tail_stats_no_prelude_ok phase=type_name_table ...`
- `p2_debug_filter_no_variadic_splat_ok`
- `p2_generated_stage2_no_prelude_interp_ok`

Latest generated-stage2 frontier:

- `s1 -> s2b` builds with `/tmp/cv2_puts` in about `241s`.
- Opt-in LLVM tail diagnostics (`ADAMAS_TRACE_STDERR=1
  ADAMAS_LLVM_REACHABILITY=1 ADAMAS_LLVM_TAIL_STATS=1`) show that
  the backend tail helpers are not the current timeout root: on the full
  compiler build, `generate(io)` reaches `finalize_enter` after emitting about
  `180.6MB` of LLVM IR. `emit_type_name_table` is the largest tail-size jump
  (`~27.8MB`, `21694` types) but only costs about `166ms`; the 300s timeout
  happens after IR generation has completed and before the produced stage2
  binary can be linked. Treat the active frontier as total generated-IR volume
  and pre-llc budget, not a single slow tail helper.
- Generated `s2b` no-prelude no-codegen smoke moved past
  `Class$Dcrystal_type_id`, `Char$Hascii_control$Q`,
  `Printer$Dshortest$$Float32_IO`, and the top-level no-prelude `puts`
  semantic error. `regression_tests/p2_generated_stage2_no_prelude_interp.sh
  /tmp/cv2_puts` is now green.
- Generated `s2b` no longer aborts on `STUB CALLED: Tuple$Heach$$block`
  for the tiny no-prelude runtime repro `puts 7`. The root cause was that
  `AstToHir#emit_runtime_print_fallback` inferred "prelude IO print is
  available" from ambient method tables instead of the actual compile mode.
  In generated stage2 that drift disabled the runtime no-prelude print path
  and let `puts` fall back into the variadic tuple corridor. `AstToHir` now
  receives `options.no_prelude` from CLI and treats `--no-prelude` as a
  hard gate for runtime print fallback selection. Evidence:
  `regression_tests/stage2_no_prelude_puts_runtime_repro.sh
  /tmp/cv2_noprel_printfix` -> `not reproduced`, while
  `regression_tests/p2_generated_stage2_no_prelude_interp.sh
  /tmp/cv2_noprel_printfix` stays green.
- Root moved: type-literal `crystal_type_id`/`crystal_instance_type_id`
  must lower to an `Int32` type-id literal before both `lower_call` and
  `lower_member_access` rewrite type literals to static `Class.*` targets.
  `Char#ascii_control?` is a leaf predicate on the raw `Char` codepoint and
  now lowers inline as `self < 0x20 || self == 0x7f`. The shape guard rejects
  both stale `Class.crystal_type_id` / `Class#crystal_type_id` and
  `Char#ascii_control?` self-host MIR targets. Separately, `TypeInferenceEngine`
  debug strings now evaluate lazily, so disabled debug hooks no longer trigger
  `Object#to_s(io)` on compiler-internal objects and accidentally materialize
  float-printing stubs during generated-stage2 semantic inference. Receiverless
  semantic inference now also treats top-level `puts`/`print` as builtins,
  matching the HIR lowering corridor.
- Generated `s2b` also moved past the debug-filter tuple-splat abort:
  `debug_env_filter_match?`, `debug_hook_filter_match?`, and
  `debug_class_repair_enabled_for?` are fixed-arity helpers now. The root was
  bootstrap-hot debug support depending on variadic `*texts`, which generated
  calls to unlowered `Tuple(String)#..._splat` helper bodies before actual
  compile work could proceed. Current `puts 7 --no-prelude` full-codegen
  frontier is now `STUB CALLED:
  Tuple$LString$C$_Crystal$CCMIR$CCType$R$Hjoin$$IO_String_block`, while
  `--no-codegen` stays clean.
- The tuple `join` frontier was localized with lldb to
  `LLVMIRGenerator#emit_extern_call`: `arg_entries.map { |(t, v, _)| ... }`
  forced tuple formatting in generated stage2. That formatter is now an inline
  indexed builder.
- The generated-stage2 `Crystal::EventLoop#close(IO::FileDescriptor)` frontier
  is cleared. Root cause: HIR materialized inherited virtual-dispatch targets
  (for example `Polling#close(Crystal::System::FileDescriptor)`) but final HIR
  RTA pruned them, and MIR later refused to use the unique same-arity inherited
  implementation for the narrower typed suffix. HIR now records lowered
  virtual-dispatch targets as final-RTA roots, inherited resolved targets are
  exact-demanded for lazy RTA, and MIR permits typed-suffix arity fallback only
  when the same-method/arity candidate is unique. The old abstract
  `Crystal$CCEventLoop$Hclose$$IO$CCFileDescriptor` stub is now a regression.
- The generated-stage2 no-prelude `puts 7` full-codegen/link corridor is now
  cleared. The kept artifacts proved the HIR/MIR/LLVM body was already good:
  the old generated compiler emitted `.ll` and a valid Mach-O object but left
  only `.o.cmdtmp` and no final executable. Root chain:
  `Crystal::System::Process.fork` was mis-lowered in the generated compiler as
  a plain `Int32` contract, so the parent compiler also entered the child
  `execvp(llc)` path and skipped the rename/link tail; after switching to raw
  `LibC.fork`, `LibC.waitpid(..., out status, ...)` exposed a second bootstrap
  lowering bug where status storage decoded pointer garbage; the runtime-stub
  freshness check pulled an unlowered `Time#<=>` stub; and the LLVM cache path
  accepted stale/empty artifacts through `File.exists?` + `FileUtils.cp`.
  The CLI tail now uses raw `LibC.fork`, explicit `pointerof(status)`, avoids
  Time ordering in the stub freshness gate, requires non-empty LLVM cache
  artifacts, and copies cache files through a small LibC read/write helper.
  `p2_generated_stage2_no_prelude_puts_guard.sh` now ends with plain
  `p2_generated_stage2_no_prelude_puts_guard_ok`.

- The generated-stage2 `File.new_internal` crash is cleared. Root cause:
  tuple element type recovery only indexed leaf alias suffixes like `Handle`,
  so a full-prelude tuple element observed as `File::FileDescriptor::Handle`
  did not resolve through the canonical
  `Crystal::System::FileDescriptor::Handle => Int32` alias. HIR then typed
  `File.open(...)[0]` as a pointer-shaped handle and LLVM emitted
  `load ptr` from the tuple slot followed by `load i32` from that fd value.
  Alias registration now indexes compound suffixes such as
  `FileDescriptor::Handle`, and qualified alias-chain fallback uses only
  compound suffixes (not broad leaf-only matches). The regression
  `p2_file_open_tuple_handle_alias_shape.sh` asserts that
  `File.new_internal` loads the fd tuple element as `i32` and calls
  `File.new(String, Int32, String, Bool, Nil, Nil)`.

- The generated-stage2 `NamedTuple(Span, ExprId, ExprId)#[](Symbol)` smoke
  stub is cleared. Root cause: generic type materialization resolved the full
  `NamedTuple(name: Type)` entries as ordinary generic parameters before the
  NamedTuple-specific parser ran. For namespaced value types such as
  `Adamas::Compiler::Frontend::Span`, this erased field names and
  materialized a positional `NamedTuple(Span, ExprId, ExprId)`, so
  `branch[:condition]` lowered to a runtime `NamedTuple#[](Symbol)` call
  instead of a static `index_get`. `NamedTuple` generic args are now parsed
  before generic substitution; only the value side is resolved and the original
  keys are rebuilt. The regression
  `p2_named_tuple_annotation_keys_no_prelude.sh` negative-checks the old
  keyless HIR shape and requires `index_get`.

- Next frontier: generated `s2b` still builds, but both smoke tests now abort
  immediately in
  `CLI#debug_cli_root_block_state(String, AstArena, Array(ExprId))`. Do not
  attempt `s3b+` until this generated-stage2 debug-helper stub is root-caused
  and guarded. The previous `NamedTuple(Span, ExprId, ExprId)#[](Symbol)`,
  `Tuple$Heach$$block`,
  `debug_env_filter_match?..._splat`,
  `Tuple(String, Crystal::MIR::Type)#join(IO, String, &block)`,
  `Crystal::EventLoop#close(IO::FileDescriptor)`, and generated-stage2
  no-prelude `puts 7` full-codegen/link repros are now green/regression-guarded.

Boundary: `src/adamas.cr --no-prelude` still exits `11` in an
inline-yield recursion / force-return corridor before it can serve as a green
pending-budget oracle.

- The generated-stage2 lookup/lazy-enum no-prelude frontier is cleared. Root
  causes:
  - hot `lookup_function_def_for_call` fallback sites called
    `function_def_overloads(...)`, whose basename collides with the
    `@function_def_overloads` ivar getter in generated stage2; a wrapper
    (`function_def_overload_keys`) keeps those hot sites away from the getter
    overload family, so local `overload_keys` no longer becomes the backing
    Hash.
  - lazy enum source-discovery state used inline-default ivars outside the
    explicit AstToHir constructor/reset corridor. Generated stage2 can leave
    those inline ivars nil, so the state is now explicitly initialized in both
    `initialize` and `bootstrap_reset_constructor_tail`.
  - lazy enum source discovery was running under `--no-prelude`, where there
    is no prelude sibling graph to recover. That made an ordinary
    `private class Hidden` reducer scan the temp directory through `Dir.glob`.
  `lazy_discover_enum_from_source` now returns false in no-prelude mode.
  Guard: `p2_generated_stage2_lookup_lazy_enum_no_prelude.sh`.
- The `Array(Box)#unsafe_fetch$Int32` no-prelude backend frontier is cleared.
  Root cause: LLVM `emit_extern_call` treated the qualified method suffix
  `$Int32` as return-type evidence, even though it is the index argument
  specialization. Calls were emitted as `i32` and the missing-body pass
  synthesized an abort stub for `Array$LBox$R$Hunsafe_fetch$$Int32`.
  The backend now keeps suffix-return hints only for bare primitive helpers and
  materializes a generic late `Array(T)#unsafe_fetch(Int32)` body using the
  element ABI from `Array(T)`. Guard:
  `p2_array_class_ref_unsafe_fetch_no_prelude.sh`; related checks:
  `p2_array_struct_unsafe_fetch_return_no_prelude.sh`,
  `p2_bootstrap_semantic_emit_oracle.sh`, and
  `p2_generated_stage2_lookup_lazy_enum_no_prelude.sh`.
- The generated-stage2 full-prelude `MacroExpander#resolve_scoped_macro_value`
  null `String#empty?` crash is cleared. Root cause: `lower_if` routed the
  main `if` condition through condition-context short-circuit lowering, but
  lowered `elsif` `&&`/`||` conditions as value expressions and then truthy-
  checked the nil-or-bool result. Generated `s2` miscompiled
  `elsif name && constant_like_name?(name)` so the nil path still reached
  `resolve_scoped_macro_value(name, context)`. `elsif` conditions now create
  their target blocks first and route short-circuit operators through
  `lower_short_circuit_condition`. Guard:
  `p2_elsif_short_circuit_condition_no_prelude.sh`.
- The generated-stage2 full-prelude lib-registration frontier has moved past
  the source-backed extern helper stubs and the invalid parser-slice helper
  calls. Root causes cleared in this corridor:
  - source-backed extern registration exposed redundant `ArenaLike` and mixed
    nilable/concrete lib-name helper signatures, so generated stage2 emitted
    concrete symbols whose bodies were registered under broader overloads;
  - `safe_str_guard` inlined pointer validation at broad `case` sites, losing
    branch-local Slice narrowing and freezing
    `Hash(String, Hash(UInt32, Crystal::HIR::Value))#to_unsafe`;
  - visibility unwrap helpers relied on `current.is_a?` narrowing for a broad
    `Frontend::Node` local, so generated stage2 emitted virtual
    `Node#expression` and then `Hash(... )#null_ptr?`;
  - reparsed macro-body root selection used block-heavy
    `program.roots.map { ... }.find(&.is_a?)` plus unchecked `arena[id]` at a
    boundary already known to be arena-fragile.
- The generated-stage2 full-prelude macro-condition frontier in
  `MacroNumberValue.numeric_suffix` is cleared. Root cause: the fixed numeric
  suffix table used `Array#find` with a block. Generated `s2` lowered that into
  an Array loop with an uninitialized cursor and crashed before the first
  `String#ends_with?`. A first attempt using `while + unsafe_fetch` was
  refuted because it still used an Array and regressed s2 build to corrupted
  `ExprId`; the accepted version keeps the existing hard-coded suffix table
  semantics but spells it as direct `ends_with?` checks with no Array/block
  machinery. Current evidence: `crystal build src/adamas.cr -o
  /tmp/cv2_numeric_suffix_chain_candidate --error-trace` passed;
  `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_numeric_suffix_chain` builds `s2`, passes no-prelude smoke,
  and advances plain smoke to `resolve_lib_global_decl_from_source(Span,
  ArenaLike)` during `LibC` registration.
- The generated-stage2 full-prelude lib global source-recovery stub is
  cleared. Root cause: `resolve_lib_global_decl` delegated to a one-use helper
  with an explicit `ArenaLike` parameter, recreating the same source-helper ABI
  boundary that previously broke extern source recovery. Adding the helper to
  exact-demand was refuted (the same stub remained), so the accepted fix
  removes the helper boundary and performs source recovery directly in
  `resolve_lib_global_decl` using `@arena`. Current evidence: `crystal build
  src/adamas.cr -o /tmp/cv2_lib_global_inline_candidate --error-trace`
  passed; `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_lib_global_inline` builds `s2`, passes no-prelude smoke, and
  advances plain smoke past full `LibC` registration to
  `detect_method_yield(DefNode, ArenaLike, Bool)` during `Errno` enum
  registration.
- The generated-stage2 full-prelude method-yield helper stub is cleared.
  Root cause: `detect_method_yield` was a tiny wrapper around already-lowered
  yield scanners, but generated `s2` materialized the wrapper's broad
  `DefNode, ArenaLike, Bool` symbol without lowering its body. Adding it to the
  exact-demand allowlist was refuted (same stub remained). The accepted fix
  removes the wrapper boundary and inlines the source-scan/fallback selection
  at the three method-registration call sites. Current evidence: `crystal
  build src/adamas.cr -o /tmp/cv2_detect_yield_inline_candidate
  --error-trace` passed; `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_detect_yield_inline` builds `s2`, passes no-prelude smoke, and
  advances plain smoke to `record_phase0_body_infer_walk(DefNode, ArenaLike,
  ExprId?)` during `Errno` enum registration.
- The default generated-stage2 phase0 body-inference metric helper frontier is
  cleared. Root cause: `record_phase0_body_infer_walk` and the canonical
  identity helper chain are diagnostic/identity bookkeeping, but default
  bootstrap smoke executed them unconditionally and exposed broad
  `ArenaLike`/nilable helper symbols. Inlining only the first wrapper moved the
  stub one layer deeper to `canonical_def_identity_for_body_infer`; the accepted
  fix gates canonical identity calculation behind `ADAMAS_PHASE0_METRICS`
  or `ADAMAS_IDENTITY_DRY_RUN`, preserving opt-in metrics/dry-run while
  removing default nonsemantic work. Current evidence: `crystal build
  src/adamas.cr -o /tmp/cv2_phase0_gated_candidate --error-trace` passed;
  `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_phase0_gated` builds `s2`, passes no-prelude smoke, and
  advances plain smoke to semantic body inference:
  `infer_concrete_return_type_from_body_inner(Array(ExprId), String, String,
  ArenaLike, Bool)`.

## Next Work

0aa. (2026-06-14) Current frontier = s2b STARTUP repr-flip (String<->Slice).
   UPDATE 2026-06-17: one confirmed producer of this family FIXED — see 0a-side6
   (SplatNode/UnaryNode NodeKind collision in lower_node; glob backtrace named it
   directly). Re-measure the s2b/glob crash rate before assuming 0aa is closed.
   lldb-VERIFIED root (memory `s2b-startup-crash-rc-overfree-refuted`): a
   header-less pointer INTO the source buffer is written into a `String`-typed
   SLOT (`HIR::Call#method_name` class field, `DefParamInfo#type_annotation`
   struct field); consumers (`parse_method_name_compact`, `ascii_suffix_bytes?`,
   `String#byte_at`) read the "header" as source ASCII -> huge bytesize -> OOB
   read. ASLR-gated non-determinism (deterministic overshoot; ASLR decides
   mapped vs unmapped). Baseline ~7/8 crash on `src/adamas.cr`. RC-over-free
   REFUTED (no-op-free A/B identical). Allocating helpers (substring/byte_slice/
   String.new(slice)) are correct; the bug is the SLOT receiving a Slice/source
   pointer at a union/phi/struct-ABI boundary.
   PLAN C (user-chosen): (A) producer localization, then (B) MIR load/store-size
   verifier. (A) IN PROGRESS: badstr probe (env `ADAMAS_BADSTR_PROBE`, throwaway,
   stash `throwaway-s2b-heisenbug-probes`) hooks all 11 `HIR::Call` ctors with
   `HIR.badstr_probe_write` -> logs `[BADSTR-WRITE] <where>` at the producer;
   self-calibrates on the live V2 header word (==16) so stage1 stays silent.
   Build debug s2b with probe, run on `src/adamas.cr` to capture first bad write.

0ab. (2026-06-14, SHIPPED `652a629a`) Producer fixed for the 0aa repr-flip:
   `Array#each_with_index` dropped loop-carried accumulation. `parse_def_receiver_name`
   sums part sizes through `each_with_index` (`total += part.size`); the DIRECT
   accumulation became a self-referential header phi (back-edge read via post-pop
   `lookup_local`, which reverts block-scope writes to the header phi) -> `total=0`
   -> `Bytes.new(0)` under-alloc -> source-pointer-in-String-slot overflow. Fix:
   two-phi scheme + dual body-exit resolution (pre-pop snapshot if it advanced past
   the header phi, else post-pop lookup for nested inline-yield). Reducer
   `regression_tests/array_each_with_index_accum_repro.sh` (direct c1-c3 + nested
   c4-c5). Suite 158/158 + 31/31. Memory `each-with-index-accum-drop-fix`.
   NOTE: measure s2b crash-rate impact; do NOT assume it alone clears the Heisenbug
   (the repr-flip SLOT bug may also be reached by other producers).
   FAMILY FOLLOW-UP (SHIPPED 2026-06-14, branch `loop-family-nested-accum-fix`):
   extracted shared `resolve_loop_backedge_value` helper (pre-pop snapshot if it
   advanced past the header phi, else post-pop resolve) and routed it through
   `times`, `range each`, `array each` (static+dynamic), `upto/downto` (Part A
   back-edge + Part B exit phi), and DRY-refactored `each_with_index`. upto/downto
   additionally re-point `@inline_caller_locals_stack[-1][var]` at the exit phi at
   loop exit (they exit via the increment block, so the header phi the inline
   caller-local was pointed at on entry is one iteration stale). hash#each was
   already correct (resolve path + cond-block exit). Reducer
   `regression_tests/loop_family_nested_accum_repro.sh` (direct d1-d8 + nested
   n1-n7). Gates 158/158 + 31/31. Memory `each-with-index-accum-drop-fix`.
   TWO CARVE-OUTS (separate root causes, NOT in this commit):
   (1) `string each_char` nested-yield accumulation: `lower_string_each_char_intrinsic`
   uses plain `ctx.lookup_local` (84651) not `lookup_local_for_phi`, so no phi is
   created for a nested accumulator -> stays at init. Needs the inline_vars phi
   plumbing the array lowerings have. Direct each_char works.
   (2) `next` inside a loop block freezes the accumulator at init for upto/downto/hash
   (direct) and ALL loops (nested). VERIFIED downstream of HIR (no-prelude HIR
   computes the right value but runtime=0); lead = loop exit phi references the
   fall-through-only value, not the next/fall-through merge (incr-phi). Memory
   `loop-next-exit-phi-drop-bug`. Repros in /tmp/loopfam (advall.cr, advdirect.cr).

0ac. (2026-06-15, SHIPPED `cb25a911`) Globber union-array late-generic template
   stride OOB — a CONTRIBUTING layer of the 0aa s2b startup crash (NOT the whole
   thing). `emit_dead_code_stub` synthesizes `Array(T)#<<`/`#push`/`#unsafe_fetch`
   bodies for generics RTA references but never lowers. Three oracles disagreed on
   the union slot stride: realloc grew by `llvm_store_size_bytes` (hardcodes 16 for
   any `.union`), store/read used a typed `getelementptr <union>, ptr %buf, i64 %idx`
   (= LLVM sizeof 20 for `{i32,[4 x i32]}`), while the array literal alloc +
   emit_array_get read used the MIR size (`container_elem_storage_size_u64` = 24).
   For Dir::Globber's PatternType union the buffer was grown by 16, written at 20,
   read at 24 -> Array#<< OOB -> heap corruption in Globber#single_compile. Fix:
   route both templates' realloc + store/read strides through
   `container_elem_storage_size_u64` and emit byte-offset gep (`%byte_off = mul i64
   %idx64, <stride>` + `getelementptr i8, ptr %buf, i64 %byte_off`); shared
   `array_element_mir_type_from_mangled_method` helper. gmalloc-VERIFIED: the old
   binary crashes deterministically in `Globber#single_compile`, the fixed binary
   sails past into normal prelude parsing. Suite 158/158 + 31/31. IR-form guard
   `regression_tests/array_late_generic_union_stride_repro.sh` (validated separator:
   pre-fix build emits the typed direct-index store, fixed build emits 0).
   DOES NOT fully clear the Heisenbug: the non-deterministic pass3/lower_main
   segfault persists (~30%, present in pre-fix builds too — single_compile was only
   the gmalloc-deterministic EARLY manifestation; the runtime crash was always at
   codegen pass3). A/B N=40: OLD 15ok/16segv/9other -> NEW(fix) 21ok/12segv/7other.
   The remaining pass3 crash is the next layer of 0aa (whole-backend window after
   `pass3 after lower_main call`; likely the repr-flip String-slot family). Memory
   `s2b-startup-crash-rc-overfree-refuted`.

0a-side. (2026-06-14, SHIPPED `56ae947b`) Found+fixed en route: macro
   `{% for x in @type.instance_vars %}` (and @type.methods) never iterated in the
   HIR lowering path (`macro_for_iterable_values_with_context` had no
   MemberAccessNode/CallNode case) -> stdlib `Struct#==`/`#hash`/`#to_s` collapsed
   -> `Hash(SomeStruct,V)` merged all distinct keys into one bucket (incl.
   compiler-internal `CallSignature`). Fix delegates to new
   `MacroExpander#evaluate_for_iterable`. Gates: combined 31/31, originals 157/157;
   regression `struct_type_instance_vars_for_loop_repro.cr`. NOTE: likely
   INDEPENDENT of the 0aa repr-flip crash (different mechanism) — measure impact
   on s2b crash rate, do not assume it fixes the Heisenbug. Named-type reflection
   (`Foo.instance_vars`) in method bodies is a separate, still-open gap (needs
   expander symbol-table wiring).

0a-side2. (2026-06-15, SHIPPED `421bed2f`) Found+fixed en route: `Pointer(T).new(
   integer_address).value` returned `address & 0xFF` instead of loading from memory.
   The element type T was dropped, so the inttoptr result was typed as a bare/UInt8
   `Pointer`; `emit_load`'s packed-scalar shortcut (llvm_backend.cr:~17831 — fires
   when `@inttoptr_value_ids.includes? && !ptr_is_typed_pointer`) then emitted
   `ptrtoint ptr to <elem>` instead of a real `load`. Fixed all 3 lowering paths by
   deriving the result element type from the owner via `method_owner(owner) ->
   Pointer(T)`: call-site path (`lower_pointer_new_intrinsic` now takes `owner_name`,
   threaded at all 3 call sites as `target_name`/`full_method_name`), with-prelude
   path (result type had resolved to the method *Class* type `Pointer(Int32).new$UInt64`,
   which naive `rchop(".new")` could not strip — `method_owner` handles the suffix),
   and the no-prelude intrinsic `lower_primitive_pointer_new_intrinsic` (with
   `@current_class` fallback). `to_unsafe`/`malloc`/`.as(T*)` were never affected
   (concrete element type). Verified runtime: 777 / 1234567890123 / 65 (with-prelude),
   exit 123 (no-prelude). Regression `regression_tests/pointer_new_value_load_repro.sh`.
   Gates 158/158 + 31/31 (identical to baseline). NOTE: OFF the 0aa #4 crash path
   (that uses `.as(UInt64*).value`), but it DID corrupt the in-s2b badstr probe (which
   read tid headers via `Pointer.new(addr).value`) — those tid numbers were artifacts;
   use external lldb for #4. Memory `pointer-new-value-element-drop-fix`.

0a-side3. (2026-06-15, SHIPPED `9f5e4acc`) Found+fixed en route: macro-built
   `Slice(T).literal` tables (the stdlib `String::CHAR_TO_DIGIT` pattern) collapsed
   to a single element. FIVE independent root causes: (1) the parser kept only the
   FIRST statement of a multi-statement `{% ... %}` directive and fast-forwarded over
   the rest (table-builder mutations never ran); (2) the macro evaluator lacked
   `Array#each`/`each_with_index`, `MacroArrayValue#[]=`, and Range-as-value
   materialization (`(0...256).map { ... }`); (3) the class-body macro-if "flag text"
   fast path did not thread macro locals (`{% table = ... %}`) into a later
   `{{ table.splat }}`; (4) `pack_splat_args_for_call` packed the splat into a Tuple
   for the `slice_literal` primitive, collapsing it to one element; (5) negative
   literals (`-1`) in the macro-reparsed builder mis-lowered because UnaryNode operator
   text was read via stale source-span extraction (offsets relative to the transient
   reparse buffer) -> garbage char -> `1.<garbage>()` STUB. Fixed by owning
   UnaryNode.operator bytes (`@operator_str`) and preferring them. CHAR_TO_DIGIT is now
   a correct 256-element slice. Reducer `regression_tests/macro_slice_literal_table_repro.sh`
   (positive-fill flag-path + CHAR_TO_DIGIT-shaped negative-fill). Gates 158/158 + 31/31.

0a-side4. (2026-06-15, SHIPPED `c92aa559`) Found+fixed en route: `String#to_i(base)` /
   `to_i32(base)` dropped the base argument. The lower_call intercept matched "any args
   count" and always emitted the decimal-only `__adamas_string_to_i` intrinsic, so every
   non-decimal conversion parsed as base 10 (`"ff".to_i(16)` -> 0, `"101".to_i(2)` -> 101,
   `"z".to_i(36)` -> 0). apply_default_args (earlier in lower_call) already materializes the
   first positional `base` param into args[0]; when present, route to a new base-aware
   intrinsic `__adamas_string_to_i_base` (strtol with runtime base, args[0] cast to Int32).
   No-arg decimal fast path unchanged. strtol covers bases 2..36; base 62 not handled.
   Reducer `regression_tests/string_to_i_base_repro.sh` (255/12/5/35/15/42). Gates: combined
   31/31, originals 157/158. The one failure (`stage2_dir_glob_dir_probe`) is the pre-existing
   non-deterministic lower_main repr-flip crash (0aa), NOT this change: A/B N=24 baseline
   (incl. CHAR_TO_DIGIT fix) 1 crash, with-diff 2 crash — sampling noise. CONFIRMS 0ac:
   neither the CHAR_TO_DIGIT nor the to_i fix clears the 0aa pass3/lower_main Heisenbug
   (~4-8% on the 3-line glob probe). #4 frontier remains the repr-flip String-slot family.

0a-side5. (2026-06-16, SHIPPED `3230c001` + test `c61b7913`) Found+fixed en route: one
   consumer of the 0aa repr-flip. `9f5e4acc` made `unary_operator_text` /
   `safe_unary_operator_string` prefer `safe_slice_to_string(node.operator)` over bounded
   source-span extraction (needed for macro-reparsed `-1` / CHAR_TO_DIGIT / to_i(base)).
   When the #4 String<->Slice repr-flip corrupts the operator slice slot (lldb-captured
   `{ptr=0x100000000, size=311}`), `String.new(slice)` memmoves past mapped memory and
   SIGSEGVs in force_lower of the Dir.glob path. Fix: new `operator_slice_to_string?`
   length-guards `node.operator` (1-4 bytes; real operators <=2: `->`, `&-`) before
   dereferencing; reading `.size` is safe (no deref). Corrupt huge-size slice now falls
   through to the bounded source-span path. Keeps 9f5e4acc's macro-reparse correctness.
   A/B (glob probe, N=40 standalone, ASLR on): operator-slice SIGSEGV 3/40 -> 0/40 (+0 in
   30 lldb tries, +0 in a 60-iter hunt). Reducer
   `regression_tests/operator_slice_corrupt_guard_repro.sh` (manual N-iter SIGSEGV guard).
   Gates 158/158 + 31/31. NOTE: this is a CONSUMER guard restoring the crash-safety
   9f5e4acc removed (regression fix), NOT a 0aa root fix — the producer repr-flip remains
   open. Residual rare rc=1 (a separate non-segfault #4 manifestation, did not reproduce
   in 60 tries) is the next thread on the 0aa frontier.

0a-side6. (2026-06-17, SHIPPED locally — pending commit) ROOT FIX for a confirmed
   0aa #4 producer: `SplatNode` misdispatched as `UnaryNode` in the `lower_node`
   fast `case kind` prefilter. `SplatNode` has no dedicated `NodeKind` and shares
   `NodeKind::Unary` with `UnaryNode` (ast.cr `SplatNode#node_kind` / static
   `self.node_kind(SplatNode)` both return `Unary`; awk-verified Unary is the ONLY
   many-to-one NodeKind collision). The `when NodeKind::Unary` branch
   (ast_to_hir.cr:52229) did an unconditional `node.unsafe_as(UnaryNode)`. Layouts:
   `SplatNode = span + expr:ExprId` (small alloc); `UnaryNode = span +
   operator:Slice(16B) + operand:ExprId + operator_str:String`. `UnaryNode#operand`
   sits PAST the end of SplatNode's smaller allocation, so the cast read `operand`
   from adjacent heap (the source-text buffer) -> a bogus ExprId = the #4
   "source-bytes-in-a-typed-slot" producer. Confirmed by the captured glob backtrace
   (/tmp/glob4_oob_full.txt): `lower_node:52230 (NodeKind::Unary) -> lower_unary ->
   lower_expr -> "ExprId out of bounds: 1701869637"` inside
   `Path.new$(Path|String)_Tuple()` (the splat-param expansion in Dir.glob — the
   exact path 0ac/0a-side5 were chasing). Fix: guard the cast —
   `unless node.is_a?(SplatNode)` — so only a real UnaryNode is unsafe_as-cast;
   SplatNode falls through to the type-safe `case node` arm (52399-52401) that lowers
   it via `lower_expr(node.expr)`. +11/-1, single hunk. Deterministic reducer
   `regression_tests/splat_node_unary_dispatch_repro.sh` (`[*t, 9]` array-literal
   splat in a top-level-called method routes a SplatNode through the exact branch):
   pre-fix rc=11 SIGSEGV in HIR lowering, post-fix rc=0; A/B reconfirmed on the live
   binaries. Gate: 161/161 originals + 31/31 combined, ALL SUITES PASSED (baseline
   was 159; suite grew, 0 new regressions). `bin/adamas` promoted to the fixed binary
   (md5 c63f1832...); scratch `bin/adamas_dbg` removed.
   CALIBRATED SCOPE (anti-theater): this removes ONE confirmed producer of the
   ExprId-OOB / source-pointer-in-String-slot family — the one the glob backtrace
   names directly. It does NOT by itself prove the whole 0aa Heisenbug is gone:
   (a) the statistical glob probe was already in a non-reproducing layout this build
   (clean bin/adamas 0/60), so it can neither confirm nor deny residual; (b) prior
   notes warn the repr-flip SLOT may be reached by other producers. NEXT: re-measure
   the `stage2_dir_glob_dir_probe` / s2b crash rate against the promoted binary to
   quantify how much of 0aa this clears; any residual non-det pass3/lower_main segv
   is the next 0aa layer. Stage2 robustness footnote: in self-hosted stage2 subclass
   RTTI can be lost after arena storage (the reason the fast prefilter exists at all),
   so worst case `is_a?(SplatNode)` returns false -> same unsafe_as as today = no
   regression; a fully stage2-robust fix gives SplatNode its own NodeKind (4
   cross-file consumers: dispatch.cr:34, ast_cache.cr:379/720, name_resolver.cr:128)
   — deferred, higher blast radius. Memory `s2b-startup-crash-rc-overfree-refuted`.

=== ABI REWORK TRACK (branch `abi-rework`, plan `docs/abi_rework_quadr_plan.md`) ===
Owner directive: fix the two ABIs at root, not symptoms; HYP-B safety-net first
(divergence assert + freeze + verifier BEFORE the inline-constructor flip).
Sequencing 0a→0b→0c→0d(SDD)→1→2→3→5a→5b; step 4 (inline flip) on an isolation
branch; closure ABI (C) pairs with fibers. Each step: own mini-Quadr, own commit,
gate = combined 31/31 + originals 158/158 + p2_generated_stage2_* + s2b probe.

ABI-0a. (2026-06-16, SHIPPED — divergence assert) Env-gated `ADAMAS_LAYOUT_ASSERT`
   in `LayoutProbe.check_divergence`: when two phases (or one phase twice) record a
   different storage CLASS for the same `type_name`, emit a `DIVERGENCE\t<CROSS|INTRA>`
   row; abort only on CROSS in mode 2. No-op on the default path (double-gated behind
   `enabled?`/`assert_mode>0`). MEASUREMENT (hello-world, ASSERT=1): 18 CROSS + 3 INTRA
   label-divergences (premise CONFIRMED — the 3 oracles disagree), and 22 distinct
   `(type,phase,context)` rows with slot_size≠access_size, CONCENTRATED in
   `llvm/container-element` (Array(Row) 8/24, Fiber 8/144, Segment64 8/56). VERIFIED at
   `llvm_backend.cr:2781`: non-whitelisted structs get an 8-byte pointer slot — that
   slot≠access is by-design PointerCarrier indirection, NOT a corruption by itself. The
   real corruption is producer/consumer DISAGREEMENT per `(type,context)` (the cb25a911
   stride family). NOTE: label-divergence is a circular falsifier for step 1 (driving
   labels equal ≡ unifying the taxonomy = step 1 itself); the drivable metric is
   producer/consumer agreement. Gate: full suite (in progress at commit time).
   Next: ABI-0b (`ADAMAS_FORCE_STRATEGY=gc` bisector), ABI-0c (real type sizes in
   estimate_size), ABI-0d (Frontier SDD — gate before step 1).

ABI-0a' (2026-06-16, SHIPPED — operational metric). The 0a assert keyed on `type_name`
   alone, so it measured cross-CONTEXT label noise (18 "CROSS"), NOT the §2.7 operational
   bug. Refined `layout_probe.cr` `check_divergence` to two signals: (1) SLOT-CONFLICT —
   same `(type, context)` with >= 2 distinct slot sizes (intra- OR cross-phase; key includes
   context so cross-context field-inline-vs-container-pointer never fires), abort-eligible in
   mode 2; (2) DIVERGENCE — the old label signal, downgraded to REPORT-ONLY (verified mostly
   label noise: String/Fiber/Atomic slot agrees, only the storage NAME differs). VERIFIED NOT
   THEATER: first cut had a `phases_all.size>=2` gate that made it structurally inert (MIR
   logs slot=-1; HIR=field-slot and LLVM=container-element never share a context) → removed
   the phase-count gate so intra-phase conflicts fire. Re-measure on /tmp/abi_layout_probe.cr:
   15 SLOT-CONFLICT + 21 label DIVERGENCE. All 15 are intra-HIR field-slot at the 8-vs-N
   ptr-vs-value boundary = the #4 family: Slice(UInt8) 8/16, Nil|String / Nil|IO /
   Nil|Array(String) 8/16 (union ptr-vs-tagged), Time 8/24, Char::Reader 8/40,
   Time::Location::Zone 16/24. This is the B0-2 "slot born 8-byte ref_fallback then written
   N-byte value view" root, MEASURED not inferred. Diagnostic-only (default path no-op:
   `log` returns at `unless enabled?`). REVISED step-1 falsifier: drive the 15 SLOT-CONFLICTs
   toward 0 (single-sourced repr, no 8-vs-N split for one type/context). Docs: plan §2.7.1 +
   table 0a' row, SDD §4. Gate: full suite (running at commit time).

ABI-0b. (2026-06-16, SHIPPED — force-GC bisector) `ADAMAS_FORCE_STRATEGY=gc` forces
   every allocation through `MemoryStrategyAssigner` to `MemoryStrategy::GC`. One
   chokepoint: override in the `assign` loop (catches both `determine_strategy` and the
   explicit-strategy bypass); cached `self.force_gc?` reads ENV lazily (module-const
   ENV-read crash avoidance). PGO refinement is profile-data-gated → off the default
   path. Verified: `.ll` differs (−308 alloca under force-GC on an allocating probe),
   compiler rc=0, default path is a guarded no-op, known-good test gives identical
   output default vs force-GC. HYBRID-MODEL CAVEAT (owner reminder): this is DIAGNOSTIC
   ONLY, never a fix — GC stays minimal, "expand GC" is forbidden as a remedy, and GC
   env effects are USUALLY layout-masking artifacts. Read ASYMMETRICALLY: *persists*
   under force-GC ⇒ NOT a strategy bug (reliable); *vanishes* ⇒ AMBIGUOUS (real strategy
   bug OR a layout bug masked by GC's larger/zeroed/aligned allocs — confirm layout via
   LayoutProbe / step-3 verifier). Gate: full suite (in progress at commit time).
   ABI-0c REASSESSED: `TypeDescriptor` carries no size, so a "real size" must be computed
   from ClassInfo ivars = a layout oracle. Building one now = the 4th oracle the SDD
   warns against → 0c now CONSUMES step 1's `layout_of` (post-step-1 follow-up, NOT a
   step-0 lever). Next: ABI-0d (Frontier SDD — gate before step 1).

ABI-0d. (2026-06-16, SHIPPED — Frontier SDD) Wrote `docs/abi_struct_value_sdd.md`, the
   ownership contract that gates step 1 (GPT review critique #2: "single oracle" cannot be
   coded safely without it, else step 1 mints a 4th oracle). Verified all three current
   oracles against code: HIR `field_storage_size_impl` (ast_to_hir.cr:39412), MIR
   `mir_field_storage_size` (hir_to_mir.cr:6353, STRING→8 special-case + no small/large
   split), LLVM `container_elem_storage_size`/`inline_container_struct_type?`
   (llvm_backend.cr:2756/:2796 string-prefix whitelist). Contract: the MIR type REGISTRY
   owns the `repr` bit (PointerReference/PointerCarrier/InlineBytes), set ONCE at the
   `align_all_class_ivars` fixed point (co-frozen with size in step 2); registry layout owns
   offsets; `slot_size = inline? value_size : 8` via one shared helper all 3 phases READ; the
   whitelist becomes a registration predicate, not a runtime name-match. Invariant (step-3
   verifier): producer & consumer must AGREE on `(repr, slot_size, value_size)` per
   `(type, context)` — strictly stronger than `slot==access`, catches the `cb25a911`
   16/20/24 family. Guard-only (keep dedicated paths, B1a/B1c history): StaticArray, Tuple/
   NamedTuple, Proc, Pointer, Union, lib structs. NON-GOALS: no inline flip (step 4), no new
   size oracle (reads frozen registry). Step-1 falsifier: 0 CROSS rows + no new slot/access
   class + suites green. Open risks carried to step 1: String slot=8 vs object value_size;
   freeze ordering (bit set at final-align fixed point, NOT earlier); late-mono types get the
   bit at registration. Next: ABI-1 (single `layout_of`, all 3 phases read).

ABI-1 (PLAN, design-corrected 2026-06-16 — step-1 reconnaissance mini-Quadr). The SDD's
   "MIR registry owns repr, all 3 phases read it" is WRONG for the HIR reader: verified
   `field_storage_size` runs INSIDE `align_all_class_ivars` (ast_to_hir.cr:28124), a pure-HIR
   pass that completes BEFORE the MIR registry is populated → a registry-owned bit is
   unreadable at the earliest (offset-producing) site. CORRECTED ownership: single source =
   a PURE PREDICATE `LayoutContract.inline_value?(kind, size, name, is_lib)` callable in all 3
   phases, MEMOIZED as a bit on MIR `Type` for MIR/LLVM (cache, not authority). Also verified:
   `type_size(String)`→ref_fallback→8 (ast_to_hir.cr:38980) == MIR STRING→8, so the String
   field-slot CROSS row is LABEL-only (InlineBytes vs PointerReference), NOT a size bug;
   real size mismatches are container-element/late-generic (0a finding corroborated). SPLIT
   step 1 (smallest/safest first, each its own commit+gate): 1a = pure predicate + MIR memo
   (ADDITIVE, no reader change, SAFE); 1b = unify LayoutProbe storage LABEL via shared repr
   classifier (drives CROSS label rows→0, zero size change); 1c = container-element
   whitelist (llvm_backend.cr:2796) → `elem_type.inline_value?` (lone CAUTION size flip).
   Big-bang reader flip judged VULNERABLE (Adversary). Docs corrected in
   `docs/abi_struct_value_sdd.md` §3/§6/§7. Next: code ABI-1a.

ABI-1a (2026-06-16, SHIPPED — pure predicate + MIR memo, ADDITIVE/SAFE). New
   `src/compiler/layout_contract.cr`: `Adamas::LayoutContract.inline_value?(kind, size, name,
   is_lib)` — the single pure repr decision ("inline bytes at the slot, or 8-byte pointer?"),
   reproducing the CURRENT effective HIR `field_storage_size_impl` decision (class ref/ptr/
   array/proc/Nil → pointer; primitive/enum → inline; union → inline iff >pointer-word; struct
   → inline-container family OR lib OR `size>=pointer-word`; tuple → `size>=pointer-word`).
   Plus a `repr` 3-way label (for 1b) and `inline_container_family?` (the LLVM whitelist, for
   1c). MIR `Type` gains a LAZY-memoized `inline_value?(is_lib=false)` caching the predicate;
   lazy (not eager at creation) so it reads the FINAL registry size — String 8→12 and similar
   post-creation size updates would otherwise freeze a stale small/large carrier decision.
   NO oracle reads the bit yet (computed-but-unused → behavior-neutral by construction).
   Required from `mir/mir.cr`. Gate: build clean; probe UNCHANGED (15 SLOT-CONFLICT + 21
   DIVERGENCE, identical set → no behavior change); originals 158/158 + combined 31/31.
   MEASUREMENT REFINEMENT vs 0a': of the 15 SLOT-CONFLICTs, 13 are true ptr-vs-value (8-vs-N)
   repr conflicts the predicate single-sources (Slice* → inline-16; Time/Char::Reader/Span/
   Stackvec/Path → inline large; Nil|* unions → inline-16); the other 2 —
   `EventLoop::Polling::Event` 88/96 and `Time::Location::Zone` 16/24 — are value-SIZE/padding
   disagreements, NOT repr (the predicate says inline for both; the residual size split is
   owned by the size authority = step 2 freeze, not the repr bit). Open for 1c: nilable-
   reference unions (`String?`) — predicate currently says inline-16 (union>8), but the correct
   repr may be an 8-byte nullable pointer; decide when wiring the union reader. Next: ABI-1b
   (route LayoutProbe storage LABEL through `LayoutContract.repr`, drives label CROSS→0, zero
   size change — also the runtime exercise/verification of the predicate).

ABI-1c FIELD-READER HALF (2026-06-16, SHIPPED — centralize the struct-carrier threshold,
   behavior-NEUTRAL). New `LayoutContract.user_struct_inline?(size, name)` is THE single
   step-4 flip point for the non-lib struct-value carrier decision (today:
   `inline_container_family?(name) || size >= POINTER_WORD_BYTES`). HIR
   `field_storage_size_impl` (ast_to_hir.cr:~39420) now routes its small-struct →
   8-byte-pointer-carrier decision through this predicate instead of the hardcoded
   `storage < pointer_word_bytes_i32` outer-guard threshold (the guard drops the size test;
   the `return pointer_word` is gated `unless user_struct_inline?`). `inline_value?`'s struct
   clause delegates to the same helper. Result: the size split that step 4 flips for the
   inline-struct perf win now lives in ONE place, read by HIR. SPLIT vs the SDD §6 plan: the
   SDD bundled 1c as container-oracle flip + field-reader delegation; I split them — flipping
   `inline_container_struct_type?` (the LLVM container whitelist) alone CORRUPTS Array(Big)
   (Array get/set/push assume pointer stride), so that flip MOVES into step 4 (needs the
   inline Array stride/get/set/push ABI). 1c here is field-readers ONLY. Behavior-neutral
   proof: reproduces the prior threshold exactly (container families are empirically inert in
   this HIR branch — not registered is_struct); probe SLOT-CONFLICT set IDENTICAL (17 types);
   reducers byte-identical (largefield total=6, slice/small/union correct, StaticArray sa0=152
   = unchanged PRE-EXISTING by-value corruption bug, a separate #4-adjacent lead). Gate on the
   post-change binary: combined 31/31 + originals 158/158. Per owner directive
   ([[abi-slot-conflict-metric-invalid]]): consolidation is the path toward the inline-struct
   perf win (step 4), #4 fixed opportunistically on clean moves. Next consolidation: route MIR
   `mir_field_storage_size` through the contract (affects only the coverage-check optimization,
   behavior-safe); then ABI-1b (probe label unification); update SDD §6 to record this split.

StaticArray-by-value FIELD store fix (2026-06-16, SHIPPED — a clean #4-adjacent move that
   the ABI-1c note flagged as the "unchanged PRE-EXISTING by-value corruption bug, sa0=152").
   Root: `StaticArray(T, N)` stored by value into a class field wrote the SOURCE POINTER's low
   bytes into the inline slot instead of the value bytes. `register_class_types` registers
   StaticArray MIR entries as zero-sized Structs (kind=Struct, size=0 — StaticArray has no
   ivars), and `canonical_container_kind_for_descriptor` only matches `"Array("`, so the
   FieldSet memcopy decision read `struct_size=0`, hit the `if struct_size > 0` guard, skipped
   the memcopy, and fell through to a scalar `store ptr`. Fix (hir_to_mir.cr): new shared
   `static_array_storage_size_from_name(type_name)` derives the inline byte count
   (element-storage-size(T) * N) from the type name — the SINGLE source used by both the Alloc
   size path (refactored, behavior-neutral) and the FieldSet memcopy `elsif is_static_array`
   branch, so they never disagree. Kept surgical (compute at the consumer, NOT in the registry):
   globally sizing the registry would flip `inline_container_struct_type?` (gated on `size > 0`)
   to a 4-byte inline element stride for StaticArray container elements — a CAUTION-tier
   Array(StaticArray) regression — so the registry stays size=0. IR proof:
   `store ptr %sa` → `call void @llvm.memcpy.p0.p0.i64(ptr %r3, ptr %sa, i64 4, i1 false)`;
   reducer now `sa0=7 sa3=9` (was 232/1). Regression: `static_array_field_value_roundtrip.cr`
   (EXPECT inner0=7 inner3=9 getter0=7 getter3=9 marker=2222). Gate: combined 31/31 + originals
   158/158.

0. (2026-06-02) M4h family root-caused + narrow fix landed (`2444b2e0`, COMPLETED not
   VERIFIED). The s2b `union_all_reference_types?` SIGSEGV is a short-TypeRef Hash value
   confusion: the resolver minted a SHORT ghost identity for compiler-internal `MIR::X`/`HIR::X`
   (anchored short-circuit in `resolve_type_name_in_context_impl`), whose hash/==/id are never
   materialized. M4h2b canonicalizes {MIR,HIR}::{TypeRef,UnionDescriptor} to FQ before the
   short-circuit (134 canon, combined 31/31). **Blocked on TWO pre-existing bootstrap issues
   before the union fix can be validated on a running s2b** (both proven NOT caused by M4h2):
   (a) [FIXED — M4i0] a freshly-built RELEASE stage1 SIGSEGV'd in the parser
   (`parse_block_body_with_optional_rescue`) building s2b: `crystal build` links with ld64.lld
   which IGNORES `-stack_size`, so stage1 got the default 8MB main stack and the recursive
   parser overflowed on the large source. Fix in `scripts/build_stage1_original_cached.sh`:
   on Darwin force `--link-flags="-fuse-ld=/usr/bin/ld -Wl,-stack_size,0x4000000"` (system ld
   honors it -> 64MB). Validated: recipe s1b otool stacksize=64MB; release s1b builds s2b
   (S2B_EXIT=0); s2b inherits 64MB via cli.cr's clang->system-ld. The M4h2 release s2b no
   longer crashes at union_all_reference_types? — frontier moved to (c).
   (b) debug s2b dies at startup on the `Crystal::Hasher` null-self blocker (deprioritized;
   release corridor is the target).
   (c) [FIXED — M4i1b `2b95eae2`] M4i1 was NOT arena: the release s2b abort in
   `set_synthetic_main_definition_location` was `STUB CALLED: HIR::Function#definition_location=`
   — the SAME short ghost-identity class as M4h, where the narrow M4h2b allowlist left
   `HIR::Function` (and other compiler-internal MIR/HIR types) as unmaterialized ghosts. Fix:
   re-widen `registered_compiler_nested_type_alias` to the whole MIR/HIR family (drop the narrow
   allowlist; keep the `type_name_exists?("Adamas::<name>")` guard that protects user programs).
   474 canon, HIR::Function present, adversary 0 outside MIR/HIR, combined 31/31. s2b on `puts 1`
   no longer aborts on the setter and now progresses INTO lowering the actual `puts 1` call.
   (d) NEW frontier (M4i2) — ROOT VERIFIED by ASAN (M4i2c): the floating, non-deterministic s2b
   crash (seen at lower_call / collect_return_types / CLI#compile across builds) is a
   `heap-buffer-overflow READ of size 8` in `Array(Adamas::HIR::TypeRef)#dup` (-> memcpy). The
   calloc buffer is 4 bytes; dup reads 8 bytes 0-after it. `HIR::TypeRef` is a 4-byte struct
   (`id : Int32`) but dup/memcpy uses an 8-byte ELEMENT STRIDE -> over-read of adjacent heap ->
   garbage -> floating downstream crashes. Allocated in lower_call (+0x179d8). So it is an
   Array-of-struct element-size/stride codegen bug (CLAUDE.md "element stride"/struct-as-pointer),
   NOT arena-lifetime or a null ExprId. M4i2c milestone file-probe was FALSIFIED (probe shifted the
   crash; reverted). ASAN via ADAMAS_EXTRA_LINK_FLAGS=-fsanitize=address works (no GC conflict).
   M4i2d (FIXED, VERIFIED): precise root was `lower_array_map_dynamic` /
   `lower_array_map_with_index_dynamic` (ast_to_hir.cr) emitting the result `ArrayNew` with the
   SOURCE element stride while storing the BLOCK-RESULT values. The s2b case:
   `arg_value_ids.map { |id| ctx.type_of(id) }` — source `Array(ValueId)` (4-byte inline UInt32),
   result `Array(TypeRef)` (8-byte heap ptr). Buffer malloc'd count*4, stores at stride 8 ->
   heap overflow read later by `dup`. NOT a dup/ExprId/tuple/union storage change and NOT the
   global inline-struct ABI: the container-storage helpers were already correct (TypeRef->8,
   ValueId->4) and the generic Array(TypeRef) corridor was uniformly 8-byte. Fix: HIR::ArrayNew
   `element_type` is now settable; both dynamic-map lowerings patch `new_array.element_type =
   set_type` once the store type is known, so alloc==store==read/dup stride. Evidence: s2b IR
   lower_call ArrayNew strides 11x4/23x8 -> 2x4/29x8/3x1; ASAN `puts 1` heap-buffer-overflow in
   Array(...TypeRef)#dup GONE; combined 31/31; 4 p2 stride guards green (ExprId stays 8); no
   regression (HEAD and fix crash at the same pre-existing frontier). See LM-M4i2d.
   Adversary-scan clean: source->result stride class closed for map/map_with_index only;
   select/reject (source->source), zip (tuple_type), hash keys/values are all correct.
   M4i3 (FIXED): tuple container storage policy for Array/Slice + Pointer#value=. Root:
   Slice#[]=/insert_head!/merge! used Array object layout (buffer @ offset 16) on Slice
   values (@pointer @ offset 8); insert_head! stored through null. Also: ref-carrying
   Array(Tuple) and merge `out.value=` must use pointer slots / store ptr, not memcpy
   tuple body into slots; primitive Array(Tuple) literals now memcpy inline into buffers
   (LM-663). Evidence: lldb `insert_head!` null deref fixed; `Array(Tuple(UInt32,UInt32))`
   sort repro prints 1,2,3; no-prelude `arr[0][1]` prints 3; combined 31/31; p2 stride
   guards green. See LM-M4i3.
   M4i5 (FIXED): split String `#hash` ABI (bare UInt64 vs typed `Crystal::Hasher`
   protocol) and compute HIR tuple/named-tuple field storage sizes for Hash::Entry
   layout. This removed the String-hash ABI corruption and the
   `Hash::Entry(Tuple(String, UInt64, UInt64, Int32), Set(String))` 32-byte key memcpy
   into a 24-byte entry body. Evidence: combined 31/31, String#hash reducer, tuple-sort
   reducer, p2 storage guards, direct s2 compiler build, and ASAN no longer reporting the
   old Hash::Entry initialize overflow.
   M4i6a (FIXED/VERIFIED advance): constructor return-type pinning in `lower_call` no
   longer uses `owner_candidates.uniq!`, `sort_by! { ... }`, or `find { ... }`; it
   preserves FQ-first/dedup/class-info/type-ref semantics with explicit while loops. This
   removes the ASAN `lower_call+0x690f8` null deref through the
   `Array(Tuple(String, Int32))#sort!$block` corridor. Evidence: host build, combined
   31/31, p2 guards, tuple-sort reducer, ordinary `puts 1` compile/run green; ASAN s2b
   advances past the old null deref. NEW frontier M4i6b: ASAN now reports
   `__adamas_ptr_copy+0x14` heap-buffer-overflow after `lower_main` (source allocation
   8 bytes, caller frame missing). Next step: add an env/file probe to `__adamas_ptr_copy`
   with return-address, src/dest/count/elem_size, then map the caller to source.
   M4i6b (FIXED/VERIFIED advance): `__adamas_ptr_copy` return-address probe mapped the
   ASAN over-read to `Array(Adamas::HIR::TypeRef)#[]?(Int32, Int32)`, called through
   `Array(TypeRef)#[]?(Range)` from inlined TypeRef tail slices in `lower_def` and
   `lower_module_method`. The accepted fix avoids the generic Range slice corridor for
   compiler-internal TypeRef tails: `type_ref_array_tail` manually copies tail elements
   using `type_ref_array_fetch_or_void`, and the known TypeRef `[1..]` sites now use it
   (`expand_flat_block_param_types`, unbound instance wrappers, inline-yield tuple
   expansion, proc tuple destructuring). Evidence: host build green, combined 31/31,
   p2 tuple/stride guards green, tuple-sort reducer compile/run prints 1/2/3, ordinary
   `puts 1` compile/run prints 1; ASAN s2b `puts 1` no longer reports the old
   `Array(TypeRef)#[]?` heap-buffer-overflow and advances past `lower_main`. NEW
   frontier M4i6c: null `String#bytesize` after `lower_main` (`x0=0`, read at 0x4),
   likely a separate null String/metadata corridor.
   M4i6c (FIXED/VERIFIED advance): advisory enum-value tracking now rejects a null
   generated `String` before calling `String#empty?`. The lldb/ASAN frontier before
   the fix was `String#bytesize -> String#empty? -> AstToHir#track_enum_value ->
   lower_method -> lower_function_if_needed_impl`, with the `String` receiver null.
   This path only records enum metadata for values, so skipping a null type name
   preserves non-null behavior and avoids treating corrupted/absent metadata as a
   real enum type. Evidence: host build green, combined 31/31, p2 tuple/stride
   guards green, tuple-sort reducer compile/run prints 1/2/3, ordinary `puts 1`
   compile/run prints 1; ASAN s2b `puts 1` no longer reports the old
   `String#bytesize`/`track_enum_value` crash and advances to
   `Set(Adamas::HIR::ValueId).new` after `lower_main`. NEW frontier M4i6d:
   null deref inside `Set(ValueId).new`, likely another compiler-internal
   collection/storage corridor.
   M4i6d (FIXED/VERIFIED advance): after M4i1b broad canonicalization,
   root-qualified compiler id sets use `Adamas::HIR/MIR::*` names, but backend
   UInt32-alias delegates still recognized only short/`Crystal::HIR/MIR::*`.
   As a result `$CCSet$LAdamas$CCHIR$CCValueId$R.new` was emitted as the raw
   `Set(UInt32).new(initial_capacity)` path and read the nil default-capacity
   pointer as an `Int32`. Fix: extend compiler UInt32-alias set/key-hash/TypeRef
   delegate recognition to `Adamas::HIR/MIR::*`. Evidence: host build green,
   combined 31/31, p2 tuple/stride guards green, tuple-sort reducer prints 1/2/3,
   ordinary `puts 1` compile/run prints 1; ASAN s2b `puts 1` no longer reports
   the old `$CCSet$LAdamas$CCHIR$CCValueId$R.new` null deref, and IR now emits
   that root alias as a delegate to `Set(UInt32).new(nil capacity)`. NEW frontier
   M4i6e: ASAN heap-buffer-overflow in
   `Array(Tuple(String, Adamas::HIR::TypeRef, Nil|Int64, Nil|String,
   Nil|Adamas::HIR::SourceLocation))#push`, reading 64 bytes at the end of a
   64-byte buffer.
   M4i6e (PARTIAL): call arguments with tuple source/parameter shape mismatches
   now try `try_coerce_tuple_to_tuple` before numeric casts in
   `coerce_args_to_param_types`. Host gates were green, but hostile lldb/IR
   review later showed one remaining lazy `Array#<<` path: the receiver was
   `Array(Tuple(...wide...))`, while the selected method suffix was still
   derived from the narrow source tuple, so parameter-only coercion was a no-op
   and the backend later normalized the call to the wide container slot.
   M4i6f (FIXED/VERIFIED advance): container writes now coerce the stored value
   to the receiver container element type before emitting `Array/Slice#<<`.
   This rebuilds `Tuple(String, HIR::TypeRef, Int64, String?,
   SourceLocation?)` into the declared storage layout
   `Tuple(String, HIR::TypeRef, Int64?, String?, SourceLocation?)` before
   `Array#<<`, instead of passing a narrow heap tuple to a wide tuple container.
   Evidence: host build green, combined 31/31, p2 tuple/stride guards green,
   tuple-sort reducer compile/run prints 1/2/3, ordinary `puts 1` compile/run
   prints 1, ASAN stage2 build succeeds, and ASAN s2b `puts 1` no longer reports
   the old `Array(Tuple(...SourceLocation))#push` heap-buffer-overflow. NEW
   frontier M4i6g: ASAN SEGV/null read in
   `Slice(UInt8)#cmp(Tuple(String, Int32), Tuple(String, Int32), Proc)` while
   compiling s2 `puts 1`.
   M4i6g (FIXED/VERIFIED advance): block forwarding now recognizes the same
   mangled block suffix forms as the resolver (`$block`, typed `_block`, and
   arity/splat variants) and forwards `&block` as a heap Proc carrier, not as a
   raw function pointer. Root: `Array(Tuple(String, Int32))#sort!$block`
   forwarded a null block to `Slice#sort!$block`; the first raw-forwarding
   experiment changed that to a high-PC BUS because `Slice#cmp` expects a heap
   Proc object `{fn, env}` and read machine-code bytes as the Proc header.
   Evidence: final host build green; ordinary `puts 1` compile/run prints 1;
   IR for `Array(Tuple(String, Int32))#sort!$block` allocates a Proc object,
   stores `%block` at offset 0 and null env at offset 8, then calls
   `Slice#sort!$block` with that object; tuple-sort reducer compile/run prints
   1/2/3; p2 tuple/stride guards green; combined 31/31. ASAN s2 `puts 1` no
   longer reports the old null/raw block ABI frontier and advances past
   `lower_main`. NEW frontier M4i6h: invalid/wild `MIR::Type*` in
   `MIR::Type#add_element_type` during `HIRToMIRLowering#register_tuple_types`
   (lldb sample: `self=0x559`), and a separate ASAN sample saw a packed/wild
   `HIR::TypeRef` in `HIR::Module#get_type_descriptor`; treat this as the next
   tuple/type-descriptor memory/layout frontier, not as a block forwarding bug.

0b. (2026-06-02) M4j0 — DWARF debug-info emitter generates DUPLICATE metadata IDs, blocking
   `-g` s2b debugging. Repro: `ADAMAS_DEBUG_EMIT=1 scripts/build_stage2_cached.sh release <stage1>
   /tmp/s2b_dbg` fails at LLVM opt:
   `error: Metadata id is already used !... = !DILocation(line: 14130, column: 15, scope: !...)`.
   `llvm_backend.cr` has a `unique_location_id`, so this may be a cross-section / global metadata
   ID collision rather than a plain DILocation duplicate. SEPARATE diagnostic from M4i2 — do NOT
   let it gate the bootstrap; it only matters as a tooling unblock (would give source lines for
   runtime crashes like M4i2). Pursue only if the M4i2 file-probe does not pin the source.

1. Root-cause the generated-stage2 full-prelude plain-smoke frontier now past
   registration-time block/yield body inference. The enum/class body-inference
   corridor was advanced by: typed `ArenaLike` resolution for
   `infer_concrete_return_type_from_body_inner`, source-backed explicit return
   recovery for enum methods whose self-hosted `return_type` field is lost,
   skipping body-return inference for unannotated enum yield/block methods, and
   a central `infer_concrete_return_type_from_body` guard that refuses to walk
   defs requiring caller block context (`yield` or direct implicit
   `&block.call`). Current evidence:
   `/tmp/cv2_bs_s2_module_name` builds `s2` in ~237s and passes no-prelude
   smoke. Plain smoke still fails, but the wide registration-helper
   abort-stub corridor is advanced: `record_nested_type_names` now threads an
   explicit `ArenaLike`, annotation registration call sites explicitly cast
   proven `AnnotationNode` values, default include debug probes are gated behind
   `DEBUG_REG_CONCRETE_PHASE`, and the class include expansion call now passes
   exact `ArenaLike`/`Set(String)` contracts. The tuple-key alias-cache crash
   is also advanced by replacing `Hash({String, ...}, String)` alias caches
   with nested String-key maps and by rewriting `module_name_from_node` to avoid
   a lambda/map/reject block that lost captured `self` in generated stage2.
   The `body_ids_match_arena?` nilable-array frontier is also advanced by
   splitting the nilable wrapper from the non-nil `Array(ExprId)` arena-fit
   scan and adding a raw low-pointer guard. The later generated-s2 LLVM
   frontiers around broad union/concrete comparison and `Pointer(T)` parameter
   scalar classification are advanced by LM-568. The primitive `each_key`
   fallback-stub LLVM shape is advanced by LM-569: produced `s2` now builds,
   and the old `Float32$Heach_key$$block(float %arg0, ptr %arg1) ret ptr %arg0`
   verifier failure is guarded by a fast no-prelude oracle. The
   `Slice(T).literal` primitive return/lowering contract is advanced by LM-570:
   the old FastFloat `POWER_OF_FIVE_128` null table no longer appears in
   produced-s2 LLVM. Current produced-s2 full-prelude `puts 42` now advances
   past the FastFloat segfault and aborts at
   `STUB CALLED: EquivUint$Dnew$BANG$$UInt64` during early prescan. A produced-s2
   no-prelude `Slice(UInt64).literal` reducer also exposes a separate
   `Indexable$LT$R$Hequals$Q$$Indexable_block` abort before it can be used as a
   produced-stage guard. LM-651 additionally fixes the `Pointer(Void)` byte
   stride/root allocation invariant and guards it against the prior typed-array
   stride regressions. LM-652 additionally fixes the nested generic
   `Pointer::Appender(T).new(pointer)` constructor path: the specialized
   receiver is preserved through path normalization, and LLVM only applies the
   primitive pointer-address constructor shortcut to real `Pointer` receivers.
   Produced s2 still builds, but full-prelude `puts 42` still exits 139 after
   reaching later `Float` module registration; localize that remaining
   memory-corruption frontier before widening to s3b.

   M4i6i (FIXED/VERIFIED advance, 2026-06-27): the Hash default-provider
   block-wrapper frontier is advanced. Root was a three-part shape/materialization
   mismatch: block wrapper specialization was still opt-in, allocator `.new`
   fallback could keep arity-only initializer names even when typed call args
   were available, and raw block callbacks materialized as heap `Proc` values
   were passed bare to `Nil | Proc(...)` parameters instead of being wrapped as
   the non-nil union arm. Fix: enable block shape specialization by default
   (still disableable with `ADAMAS_BLOCK_SHAPE_SPECIALIZE=0`), preserve typed
   allocator initializer names when an arity match has exact typed args, trace
   raw callback sources through `Copy`/`Cast`/`UnionWrap`, materialize them as
   heap Proc objects, and immediately coerce materialized Proc values to the
   target union when needed. The raw callback source walker is bounded and
   allocation-free to avoid self-host `Set(ValueId)`/block iterator fragility.
   Evidence: new `hash_block_shape_default_proc_repro.sh` prints `A=1`/`B=0`;
   `hash_default_provider_proc_repro.sh` green; pointer-filled Array negative
   control green; full suites green (`151/151` originals + `36/36` combined);
   ASAN stage2 bootstrap builds and full-prelude plain smoke now passes. Remaining
   frontier is generated-stage2 no-prelude smoke:
   `EscapeAnalyzer#build_summary` null write under ASAN. Do not claim s2b/s3b
   green until that no-prelude frontier is localized.
2. Root-cause the remaining full-prelude nested-class return-inference crash
   under generated stage2. Current evidence: stale parameter slice frontiers are
   advanced through source-backed initializer capture, source-prefiltered
   implicit-ivar param scanning, and source-backed nested-module method params.
   The latest lldb frontier is now `infer_type_from_expr_inner` from
   `infer_concrete_return_type_from_body` while registering
   `Float::Float::Bigint` through the reparsed/generic nested-class corridor.
   First determine why registration is doing eager body inference there, and
   add a focused no-prelude oracle before changing the inference policy.
3. Run the generated-stage2 compiler on the broader fixed no-prelude corpus and
   add focused oracles for any new first failure.
4. Compare `s1_bootstrap` and `s2b` on the fixed no-prelude corpus before
   trying `s3b+`.
5. Audit remaining compiler hot paths that use tuple block destructuring or
   block `join` formatting; keep the general tuple-block fix as an explicit
   follow-up rather than hiding it with one-off stubs.
6. Add/inspect exact-called provenance for `record_pending_callee_for_rta` so
   the source of remaining `keep:exact_called Array#to_s` / `Hash#to_s` demand
   is explicit.
7. Verify whether broad fallback self-calls should mark exact concrete wrapper
   names as demanded, or whether they should remain virtual/demand-local until a
   real callsite asks for that concrete owner.

## Stop Conditions

- Do not run `s3b+` until generated `s2b` passes plain/no-prelude smokes and
  normalized corpus comparison is green.
- Do not increase timeout or memory to hide pending expansion.
- Do not modify stdlib/runtime.
- Do not land another name-family guard unless it measurably reduces the
  `~61k` process-pending expansion.
- If two more bounded containment fixes fail, pivot from heuristics to explicit
  demand-provenance design.

## Strategic Track

Architecture target:

- `PLAN_DEMAND_DRIVEN_REWRITE.md`
- `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md`

Current short-term track: bootstrap containment plus fast no-prelude oracle
coverage, not a full compile-path switch.

### LTP/WBA optimizer speedup candidates (2026-06-12 code review, NOT profiled)

V2's release-compile speed advantage over original Crystal comes from the
LTP/WBA MIR pre-optimization feeding LLVM lean IR (original's bottleneck is
LLVM -O3 on raw IR; its frontend is fast). Keeping the optimizer itself fast
preserves that lever. Candidates from reading `src/compiler/mir/optimizations.cr`
— **profile first** with the built-in `--debug-profile` per-pass timing and
A/B via `--no-ltp` / `--no-mir-opt` / `--no-llvm-opt`; only then optimize:

1. Incremental analysis after LTP moves (`LTPEngine.run` ~:2483): each applied
   move does a full `build_analysis_maps` + `compute_frame_potential` O(N)
   rebuild, up to max_iters=10 per function; a move touches one
   window/corridor — update affected blocks only. Biggest candidate on
   stdlib megafunctions.
2. Per-pass allocation churn: every pass run allocates fresh
   `Hash(ValueId,…)`/`Array`/`Set`; pipeline loops ≤4× per function. Pool and
   clear instead of new (zero-copy policy). Bonus: V2 struct ABI makes Hash
   ops extra costly in s2b, so this disproportionately speeds the bootstrap
   compiler itself.
3. Dominance recompute in CopyPropagation (`compute_dominance_info` ~:1702):
   recomputed per run; cache keyed on CFG version.
4. `find_window` full rescan per LTP iteration (~:2531): collect RCIncrement
   candidates once in `build_analysis_maps`, maintain incrementally.
5. `PeepholePass` lacks a hint gate (pipeline ~:2067): only pass that runs
   unconditionally even with zero candidates.

Healthy as-is (do not touch without a profile): hint-gated passes, DCE-2 only
after DCE-1 progress, `optimize_with_potential` monotone-potential break.
