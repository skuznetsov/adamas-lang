# Crystal V2 Bootstrap — TODO (Updated 2026-03-27)

## Current Status
- **Fresh absolute-name whitespace root cause fix (2026-03-27, current session)**:
  - decisive tiny oracle:
    `regression_tests/stage2_include_target_arena_hir_oracle.sh`
  - verified root cause:
    - after the earlier `name[2..] -> byte_slice` fix, absolute names like
      `::Pointer(self)` still reached the self-hosted stage2 consumer with a
      **trailing ASCII space**
    - direct byte trace inside `split_generic_base_and_args` proved the exact
      payload for the failing carrier:
      `tail4=108,102,41,32` (`'l','f',')',' '`)
    - the first-stage symptom was:
      `lookup=Pointer(self) has_generic=1` but `split_generic_base_and_args`
      returned `nil`, so HIR degraded to `Class Pointer(self)`
    - this also proved ordinary `String#strip` was not a safe normalization
      primitive in this self-hosted corridor
  - shipped local fix:
    - added byte-level `strip_ascii_edge_whitespace`
    - routed `strip_absolute_name_prefix`, `split_generic_base_and_args`, and
      `type_ref_for_name_inner` through that helper
  - verified outcomes:
    - `bash regression_tests/stage2_include_target_arena_hir_oracle.sh /tmp/stage1_release_29966272 /tmp/stage2_current_debug_moddefswhile`
      -> `not reproduced`
    - `scripts/run_safe.sh /tmp/run_once_noprelude_stop_after_hir_stage2_moddefswhile.sh 30 2048`
      -> green
    - trusted full follower
      `src/crystal_v2.cr --release --no-ast-cache --emit hir` under
      `CRYSTAL_V2_STOP_AFTER_HIR=1 CRYSTAL_V2_TRUST_SLICE_ADDR=1`
      is still red, but no longer on the old `once` include-helper corridor
  - new live frontier:
    - current stage3 `STOP_AFTER_HIR` trace now reaches:
      `pass1_module_before_register idx=5` with `name=SystemError`
    - crash occurs after successful module registrations for:
      `Crystal`, `Comparable`, and `Exception`
    - next reducer should pivot from `once`/`Pointer(self)` to the
      `SystemError` module-registration corridor
- **Fresh `Crystal::Once::Operation` include-helper prelude split (2026-03-26, current session)**:
  - decisive trusted oracle remains:
    `src/stdlib/crystal/once.cr --release --no-prelude --no-ast-cache`
    under `CRYSTAL_V2_STOP_AFTER_HIR=1 CRYSTAL_V2_TRUST_SLICE_ADDR=1`
  - verified narrowing on current debug self-hosted stage2:
    - second registration still reaches
      `phase=before_include_expansion count=1`
    - replacing `include_nodes.each` with `while + unsafe_fetch`, storing
      `ExprId` targets instead of `IncludeNode`, and adding a no-op helper with
      the **same full signature** as `register_module_instance_methods_for`
      all preserve the same overall crash site
    - the no-op probe prints successfully on the second registration with:
      `target=2 defs=0 class_defs=0 visited=0 visited_ext=0 ivars=2 offset=0 struct=1 init=1`
    - immediately after `include_probe_passed`, the real
      `register_module_instance_methods_for` still segfaults **before**
      printing its first internal milestone (`defs_ready`)
  - strongest interpretation:
    the active sink is no longer the outer `include_nodes` iterator, no longer
    `IncludeNode` storage/field transport, and no longer the raw multi-arg call
    ABI itself. The remaining live corridor is now the **early prelude inside**
    `register_module_instance_methods_for` before `defs = @module_defs[...]`,
    i.e. one of:
    `sanitize_type_name`, `resolve_path_like_name(include_target)`,
    `resolve_module_alias_for_include`, `record_module_inclusion`, or the fresh
    `visited` checks on the second registration path
  - practical consequence:
    next instrumentation/falsification should target those early pre-`defs`
    helper steps directly instead of widening the reducer or patching more
    iterator loops
  - update after richer probe:
    - the second registration now passes a second prelude probe through:
      `sanitize_type_name(class_name)`
    - it then segfaults **before** the next probe print
      `after_resolve value=...`
    - strongest current sink is therefore narrowed again to
      `resolve_path_like_name(include_target)` itself (or the immediate
      machinery it enters), not `sanitize_type_name`
- **Fresh `Exception::CallStack` trust-split (2026-03-26, current session)**:
  - decisive reduced oracle:
    `tmp/reduce_exception_call_stack_class_getter.cr`
    ```
    class Exception
    end

    struct Exception::CallStack
      @@skip = 0
      class_getter empty = 1
    end
    ```
  - verified behavior:
    - `stage1` is green under `CRYSTAL_V2_STOP_AFTER_HIR=1 --no-prelude`
    - self-hosted `stage2` is red **without**
      `CRYSTAL_V2_TRUST_SLICE_ADDR=1`, but that red path dies in the stale
      guard sink `safe_slice_to_string -> readable_address? ->
      LibMachVM.mach_task_self`
    - the **same** self-hosted `stage2` turns green once
      `CRYSTAL_V2_TRUST_SLICE_ADDR=1` is enabled
  - strongest interpretation:
    this reduced carrier does **not** model the current trust-enabled root
    frontier. It only proves that the old no-trust Mach/readability probe sink
    is still live on self-hosted stage2 and must not be confused with the
    deeper root blocker when the active wrapper already sets trust
  - practical consequence:
    do not chase `Exception::CallStack` through no-trust `readable_address?`
    crashes when comparing against the current root `STOP_AFTER_HIR` wrapper;
    keep trust parity first, then widen the reducer toward the real `call_stack`
    feature mix
- **Fresh reduced `Exception::CallStack` body-shape split (2026-03-26, current session)**:
  - verified trace on the same reduced carrier with trust enabled:
    - `register_concrete_class("Exception::CallStack")` completes fully, twice
      (module registration + later class registration)
    - body loop shape is:
      - `idx=0`: `AssignNode` for `@@skip = 0`
      - `idx=1`: raw body entry from the `class_getter` keyword that still
        prints as `node_kind=0` / no stable `is_a?` match in the trace
      - `idx=2`: `AssignNode` for `empty = 1`
    - despite that odd accessor-body shape, the reduced carrier still exits
      green with trust enabled
  - strongest interpretation:
    the bare synthetic namespace wrapper
    `class Exception; end + struct Exception::CallStack + simple classvar/class_getter`
    is **insufficient** to reproduce the real trust-enabled root failure. The
    next meaningful reducer must add more of the real `src/stdlib/exception/call_stack.cr`
    feature mix rather than re-debugging this already-green miniature
  - caution:
    heavy diagnostic rebuilds currently perturb the full root run enough that a
    temporary earlier crash at `once.cr` reappears; treat that as diagnostic
    noise until reconfirmed on a cleaner probe
- **Fresh Pass 1 iterator-contract split (2026-03-26, current session)**:
  - decisive verified movement on current `/tmp/stage2_current_debug_exprtrace`:
    - root carrier previously reached `pass1_before_lib_loop` and then crashed
      before any lib body progress under `lib_nodes.each_with_index`
    - replacing only the lib loop with manual `while + unsafe_fetch` moved the
      same carrier through all 16 libs and to `pass1_after_lib_loop`
    - the new follower then landed at `enum_nodes.each_with_index`
    - replacing only the enum loop with manual `while + unsafe_fetch` moved the
      same carrier through all 8 enums and to `pass1_after_enum_loop`
  - strongest interpretation:
    this is no longer a one-off `LibEntry` quirk. A real self-hosted root-cause
    family is now live in Pass 1: `Array#each_with_index` / iterator-yield
    transport over arrays of composite payloads (`LibEntry`,
    `Tuple(EnumNode, ArenaLike)`, and likely neighboring registration arrays)
    is not representation-safe on the current stage2 binary
  - practical consequence:
    the next high-signal move is no longer more tracing around prescan. It is
    systematic falsification of the same iterator contract on the immediately
    following Pass 1 arrays (`alias_nodes`, `macro_nodes`, `module_nodes`,
    `class_nodes`, `constant_exprs`, then later `def_nodes`)
  - update after systematic normalization:
    - converting `alias_nodes`, `macro_nodes`, `module_nodes`, `class_nodes`,
      and `constant_exprs` from `each_with_index` to `while + unsafe_fetch`
      moved the root carrier further again
    - root now cleanly reaches:
      `pass1_after_alias_loop`, `pass1_after_macro_loop`,
      `pass1_after_log_modules`
    - the current live follower is now **inside** the normalized module
      registration loop, not in the old iterator entry corridor anymore
  - strongest current interpretation:
    the Pass 1 iterator family is now verified and partially mitigated; the
    next frontier has moved lower to module-registration payload handling
    (`hir_converter.register_module(n)` and immediate surrounding consumers)
- **Fresh `DEF_ARENA` false-frontier split (2026-03-26, current session)**:
  - source already had `debug_def_arena_enabled_for?` effectively disabled, but
    self-hosted `stage2` was still executing the stale `DEF_ARENA` diagnostic
    corridor on `once.cr --no-prelude --STOP_AFTER_HIR`
  - decisive verified comparison:
    - `stage1` on the same carrier printed no `DEF_ARENA` lines
    - self-hosted `stage2` did print `DEF_ARENA` lines until the corridor was
      removed from `registration_member_arena_for`
    - after rebuilding `/tmp/stage2_current_debug_exprtrace`, the same carrier
      stayed green and stderr parity with `stage1` was restored for that path
  - strongest interpretation:
    this was a real false frontier, not a trustworthy live sink. A
    diagnostic-only branch that source intended to be dead was executing under
    self-hosted stage2 and was noisy enough to become its own crash source
  - practical consequence:
    the root `STOP_AFTER_HIR` frontier moved below `registration_member_arena_for`
    and should no longer be debugged through stale `DEF_ARENA` output
- **Fresh root HIR phase split below prescan (2026-03-26, current session)**:
  - decisive verified phase trace on current `/tmp/stage2_current_debug_exprtrace`:
    - `collect_done` is reached cleanly on the root carrier
    - `seed_names_enter`, `seed_type_names_after`, `seed_class_kinds_after`,
      and `seed_names_done` are all reached cleanly
    - `prescan_enter` is reached and both class and module prescan loops run to
      completion, including the last module from `src/compiler/cli.cr`
      (`prescan_module_after_scan idx=111 name=CrystalV2`)
    - only then does the root carrier still exit red (`138/139`)
  - strongest interpretation:
    the old root blocker was no longer in top-level collection, no longer in
    top-level seed helpers, and no longer in class/module prescan. That narrow
    corridor has now been further resolved by the fresh Pass 1 iterator split
    above; use that newer landmark as the current frontier
  - refuted hypotheses:
    - “root crash is inside one specific `collect_arena` iteration”
    - “root crash is inside `seed_top_level_type_names` / `seed_top_level_class_kinds`”
    - “root crash is inside `scan_module_body` for the top-level `CrystalV2`
      module in `src/compiler/cli.cr`”
- **Fresh `type_name_exists?` cache-discipline root-cause split (2026-03-26, current session)**:
  - the later repaired-`resume_all` builtin shadow is no longer best modeled as
    alias fallback and no longer as generic include-target failure
  - decisive verified trace on current `/tmp/stage2_current_debug_exprtrace`:
    - after the builtin guards in contextual/suffix alias fallback, the old
      `Crystal::PointerLinkedList::Node::Nil` sink is gone on the tiny oracle
      and on the first repaired `resume_all` resolution
    - the next follower was a later builtin-shadow path through
      `resolve_class_name_in_context -> resolve_nested_builtin_shadow`
    - instrumentation in `nested_type_shadow_in_namespace` showed bogus
      candidates like `Crystal::Once::Nil` and then `Crystal::Nil` with
      `sources=` empty, which falsified “real live type exists” and pointed to
      `type_name_exists?` cache discipline
    - a direct trace in `type_name_exists?` then verified the stable state:
      `type_name_exists?("Crystal::Nil")` computes `false`, caches a negative
      stamp, and later builtin resolution keeps `shadow=(nil)` across the whole
      repaired `resume_all` corridor
  - strongest interpretation:
    one real root-cause family is now verified lower in the stack:
    type-universe invalidation and `type_name_exists?` caching policy were not
    epistemically safe for self-hosted stage2. Builtin-shadow logic was willing
    to trust cached existence for nested candidates even when no live type
    source still supported them
  - practical consequence:
    the later `Nil -> Crystal::Once::Nil` / `Crystal::Nil` follower is no
    longer live on the current debug probe; the active frontier moved lower
    again
- **Fresh repaired-`resume_all` post-include frontier split (2026-03-26, current session)**:
  - with the builtin-shadow follower gone and
    `CRYSTAL_V2_FORCE_NO_BLOCK_IF_NO_PARAMS=1`, repaired
    `Crystal::Once::Operation#resume_all` now registers cleanly as plain
    `Crystal::Once::Operation#resume_all` and exits the `DefNode` case cleanly
  - decisive verified phase trace:
    - `after_type_param_store`
    - `after_base_name_branch`
    - `def_case_exit`
    - `after_body_scan`
    - `before_include_expansion count=1`
    - `after_include_expansion`
    - `after_untyped_reassert`
    - only then: `error: Comparison of 8 and 8 failed`
  - decisive falsifier:
    `CRYSTAL_V2_SKIP_REASSERT_UNTYPED_BASE=1` does **not** remove the crash; it
    still occurs after `after_untyped_reassert`
  - strongest interpretation:
    the live repaired-`Operation` blocker is now below method registration,
    below include expansion itself, and below the untyped-base reassert pass.
    The next narrow corridor is the post-include implicit-ivar / class-finalize
    tail (`class_body.each` implicit ivar scan and immediate follow-up)
- **Fresh builtin-alias fallback root-cause split (2026-03-26, current session)**:
  - the old `Crystal::PointerLinkedList::Node::Nil` contamination on repaired
    `Crystal::Once::Operation#resume_all` is now narrowed to a concrete alias
    resolution contract hole, not a generic include-target failure and not a
    by-value return-string transport bug
  - decisive tiny oracle:
    `regression_tests/stage2_builtin_nil_alias_repro.cr`
    (`Crystal::Once::Operation` + `include PointerLinkedList::Node` +
    `def resume_all : Nil`)
  - decisive verified trace on current `/tmp/stage2_current_debug_exprtrace`:
    - first falsifier: the old include-only hypothesis was wrong; even after
      `resolve_included_type_name` got a builtin guard, the tiny oracle still
      resolved `raw=Nil` to `Crystal::PointerLinkedList::Node::Nil`
    - second falsifier: `eq_nil=1` and `builtin_alias=1` were already true at
      `resolve_type_name_in_context_impl`, so the issue was not “this is some
      weird non-`Nil` string”
    - actual sink 1: `resolve_contextual_type_alias_name("Nil")` returned
      `Crystal::PointerLinkedList::Node::Nil` because its own contract comment
      said “Never shadow built-in/top-level type names”, but the code only
      guarded top-level names
    - after adding the builtin guard there, the same oracle moved and exposed
      actual sink 2: `resolve_type_alias_by_suffix("Nil")` still returned the
      same bogus target because it also lacked the same builtin/top-level guard
    - after adding the symmetric guard there too, the exact same tiny oracle
      now logs `resolved_return raw=Nil resolved=Nil`
  - strongest interpretation:
    one real root-cause family is now verified: builtin/core type names were
    allowed to leak through both alias-by-context and alias-by-suffix fallback
    corridors, even though those paths were supposed to be strictly secondary
    to builtin resolution
  - current boundary after that fix:
    the tiny oracle still crashes later, but only after
    `phase=after_type_param_store`; the old `Node::Nil` misresolution is gone
  - practical consequence for real `once.cr`:
    `resume_all` no longer resolves its explicit return annotation through
    `Crystal::PointerLinkedList::Node::Nil`; the live `once.cr` frontier is now
    lower and mixes:
    - a later false builtin shadow (`Nil -> Crystal::Once::Nil`) on a second
      resolution inside the same method corridor
    - the old local `has_block=1` flip, which still survives on real
      `resume_all`
    - the broader `SpinLock` / `Comparison of 8 and 8 failed` follower
- **Fresh `resume_all` local-bool corruption split (2026-03-26, current session)**:
  - the real live `once.cr` blocker is now narrowed inside repaired
    `Crystal::Once::Operation#resume_all` registration, well below
    class-repair entry and below `set_function_def_arena(full_name, ...)`
  - decisive verified trace on current `/tmp/stage2_current_debug_exprtrace`:
    - `member.receiver` reads cleanly as `nil`
    - explicit return type is parsed from source as `Nil`, but resolves as
      `Crystal::PointerLinkedList::Node::Nil`
    - `member.params` is absent (`params_present size=0`)
    - yet the local registration bool still flips to `has_block=1` before any
      yield scan, producing the bogus mangled name
      `Crystal::Once::Operation#resume_all$block`
  - strongest interpretation:
    this is not real block semantics and not a true AST params bug. It is an
    active local-slot / temporary-state corruption corridor inside
    `register_concrete_class` method registration, in the same wider family as
    earlier self-hosted wrapper/bool/value corruption
  - decisive falsifier:
    a purely diagnostic env-gated reset
    `CRYSTAL_V2_FORCE_NO_BLOCK_IF_NO_PARAMS=1` forces `has_block=0` only when
    `params.nil?`; that changes the same carrier from bogus
    `#resume_all$block` registration to plain `#resume_all` and moves the crash
    later into duplicate base-name `set_function_def_entry` replace-path
    handling. Therefore the earlier sink was caused by corrupted local state,
    not by true block metadata on the `DefNode`
  - important secondary anomaly, likely related but not yet proven identical:
    the same trace still resolves source `: Nil` to
    `Crystal::PointerLinkedList::Node::Nil`, so there is also a namespace/type
    resolution contamination corridor active on the repaired class path
- **Global stage1-vs-stage2 divergence synthesis (2026-03-26, current session)**:
  - the accumulated verified fixes no longer support the naive model
    “same source should behave the same, so stage2 is just hitting random edge
    cases”. Once the compiler becomes self-hosted, `stage2` is a new binary
    compiled by our own codegen/runtime, so any miscompile of compiler-internal
    representations shows up as a semantic difference between `stage1` and
    `stage2` even on identical source text
  - the strongest cross-session clustering now has four real root-cause
    families:
    - **family A: composite value / wrapper transport corruption**. Verified
      members: `lex_char` helper-return, escaped-char helper-return,
      enum-member nilable ctor, synthetic `HIR::Function` param storage,
      false non-nil `DefNode.return_type`, tuple / wrapper / `ArenaLike`
      transport drift. Reusable lesson: avoid by-value relocation of composite
      structs in bootstrap-hot paths; inline construction or keep raw/reference
      snapshots instead
    - **family B: ownership / arena-admission gaps**. Verified members:
      snippet-reparsed nested-module defs being stored canonically,
      shallow `arena_fits_class_node?` validation that ignored
      `IncludeNode.target` and accessor/default payloads, and the new
      class-repair frontier after `fit=0`. Reusable lesson: stage2 often fails
      not because a node is globally corrupted, but because later consumers are
      allowed to read a node through the wrong arena or after an unsafe repair
      path
    - **family C: name/slice ingestion fragility with source-derived recovery
      as the stable bedrock**. Verified members: absolute generic header leaf
      names, lib struct/class names, alias prefix extraction, explicit return
      type recovery from source. Reusable lesson: on self-hosted carriers,
      source/snippet-derived metadata is often more trustworthy than raw field
      reads from composite AST/HIR nodes
    - **family D: explicit representation-contract mismatches in MIR/LLVM**.
      Verified members: unsigned literal cache mixup, ptr-zero text rewrite
      after string-length computation, enum-owner cache-key clobber, function
      param storage drift. Reusable lesson: once the storage contract is wrong,
      later stages can deterministically diverge even when the frontend looked
      plausible
  - why edge cases fail first:
    edge cases are not random. They are high-sensitivity probes for these
    families because they disproportionately hit nilable/defaulted fields,
    union-tag paths, small helper-return values, snippet-repair corridors,
    nested ownership, and guard-heavy slice/name reads. Normal code paths can
    stay green longer simply because they avoid those representation-sensitive
    corridors
  - stale broad theories that should no longer drive debugging:
    - “there is one monolithic parser bug”
    - “the remaining blocker is just LLVM/backend”
    - “reparsed arena lifetime alone explains the class crashes”
    - “include target resolution or `Pointer(self)` alone explains `once.cr`”
  - strongest current interpretation:
    the active `once.cr` / top-level `Operation` blocker still sits in the
    overlap of families **A + B**: class registration reaches a `fit=0`
    situation, then enters a repair/reparse corridor whose nested payload
    ownership or consumer-side representation contract is still wrong. The
    already-verified deep class-member fit fix closes the earlier shallow
    admission bug, but the remaining frontier is lower: semantic/transport
    correctness of class repair after admission already failed
  - next root-cause-oriented move:
    treat `stage1` vs `stage2` as an equivalence problem for
    compiler-internal invariants, not as a generic source-language bug.
    The highest-signal next experiment is a paired trace on the same tiny
    class carrier comparing:
    1. original node + original arena
    2. repaired/reparsed node + repaired arena
    across `register_class_with_name -> register_concrete_class ->
    resolve_path_like_name_in_arena`
    If those diverge before HIR semantics diverge, the live root cause is in
    repair/ownership transport; if they stay aligned until later, the next sink
    is a consumer-side field/wrapper read inside class registration
- **Fresh class-member arena-fit root-cause split (2026-03-26, current session)**:
  - the older wide include-macro matrix is now stale. On the current local
    deep-fit worktree the verified no-prelude matrix is:
    - top-level `Operation` + included `property ::Pointer(self)` -> `stage1 green / stage2 red`
    - `A::B::Operation` + the same include -> `green / green`
    - `Crystal::B::Operation` + the same include -> `green / green`
    - `Crystal::Once::Operation` + included `property Int32 = 0` -> `green / green`
    - real `src/stdlib/crystal/once.cr --STOP_AFTER_HIR` -> still `stage1 green / stage2 red`
  - decisive verified movement:
    a local hardening of `arena_fits_class_node?` now descends into
    class-member substructure (`IncludeNode.target`, accessor/default corridors,
    typed ivar default expressions) instead of validating only outer body ids
    and outer spans. After rebuilding `/tmp/stage2_current_debug_exprtrace`,
    both previously-red nested reducers
    `tmp/reduce_depth2_include_macro_property_self.cr` and
    `tmp/reduce_crystal_depth2_include_macro_property_self.cr`
    turned `stage2 green`, while the old control
    `tmp/reduce_crystal_once_include_macro_property_int32.cr` stayed green
  - strongest interpretation:
    one real root-cause family is now verified: shallow class-member
    arena validation allowed `register_concrete_class` to proceed on class
    nodes whose nested member payloads did not belong to the active arena.
    The first concrete sink for that family was the include-target read in
    `resolve_path_like_name_in_arena`
  - new boundary after that movement:
    top-level `tmp/reduce_include_macro_property_self.cr` still reds with the
    same `resolve_path_like_name_in_arena -> register_concrete_class` stack,
    and `once.cr` still reds with `Comparison of 8 and 8 failed`
  - decisive falsifier for the next branch:
    a follow-up lifetime-only experiment that retained repaired class snippet
    arenas in `@main_arenas` made **no** difference for either the top-level
    reducer or real `once.cr`; so the remaining blocker is not explained by
    “reparsed class arena gets dropped” alone
  - strongest current frontier:
    the live blocker has moved below arena-fit admission and now sits in the
    class repair/reparse corridor after `fit=0`, not in the already-exposed
    nested include-path family itself
- **Fresh `Crystal::Once::Operation` included-macro cluster split (2026-03-26, current session)**:
  - the old broad model “nested include + `Pointer(self)` is red” is now falsified by a clean no-prelude matrix:
    - top-level `Operation` -> `stage1 green / stage2 green`
    - `A::Operation` -> `green / green`
    - `A::B::Operation` -> `green / green`
    - `Crystal::Operation` -> `green / green`
    - `Crystal::B::Operation` -> `green / green`
    - `A::Once::Operation` -> `green / green`
    - only `Crystal::Once::Operation` stays `stage1 green / stage2 red`
  - decisive falsifier: replacing `property previous : ::Pointer(self)` with
    `property previous : Int32 = 0` in the same `Crystal::Once::Operation`
    carrier does **not** heal stage2; so `self` type resolution is not the live
    blocker anymore
  - additional verified signal on the real carrier:
    `env DEBUG_MODULE_INCLUDE=1 scripts/run_safe.sh /tmp/run_once_stop_after_hir_stage2_current.sh 30 3072`
    shows `Crystal::Once::Operation <= PointerLinkedList::Node (resolved: Crystal::PointerLinkedList::Node)`
    before the same `error: Comparison of 8 and 8 failed`
  - strongest current interpretation:
    the live family is now narrower than include-target resolution and narrower
    than generic nested includes. It sits inside `Crystal::Once::Operation`
    included-macro property expansion / accessor-registration tail after the
    include target is already resolved correctly
  - rejected branch:
    a source-aware include-target resolver experiment was tried locally and then
    rolled back from the active branch after it failed to move `once.cr` and
    introduced `SIGBUS` on tiny reducers; keep the idea only as historical
    evidence that include-target recovery alone is insufficient
- **Fresh `Crystal::Once::Operation` class-arena root-cause split (2026-03-26, current session)**:
  - the old `.new` duplicate-registration model is now stale. Fresh LLDB on
    `/tmp/stage2_current_debug_exprtrace` for
    `src/stdlib/crystal/once.cr --release --no-prelude --no-ast-cache` with
    `CRYSTAL_V2_STOP_AFTER_HIR=1 CRYSTAL_V2_TRUST_SLICE_ADDR=1` lands in:
    `AstArena#[] -> VirtualArena#[] -> resolve_path_like_name_in_arena ->
     register_concrete_class -> register_class_with_name_in_current_arena ->
     register_class_with_name -> register_nested_module`
  - direct stage2 trace falsifies the older `SpinLock.new` tail:
    second-pass registration for `Crystal::SpinLock` reaches both duplicate
    `set_function_def_entry` and `set_function_def_arena` writes, reaches
    `[CLASS_INFO] Crystal::SpinLock ivars=[] size=0`, and
    `register_function_type("Crystal::SpinLock.new", ...)` also completes
    before the next crash family appears
  - new fast follower remains:
    `src/stdlib/crystal/once.cr --release --no-prelude --no-ast-cache`
    gives `stage1 green / stage2 red`
  - decisive `DEBUG_CLASS_ARENA='Crystal::Once::Operation'` signal on the same
    carrier:
    `register_class_with_name` receives `Crystal::Once::Operation` with
    `current fit=0`, `chosen fit=0`, and no better arena candidate from the
    same file; stage2 then still enters
    `[REG_CONCRETE_PHASE] class=Crystal::Once::Operation phase=after_pass0`
    and only crashes during the later include/extend scan
  - strongest current interpretation:
    the real live blocker is no longer `.new` or generic-ivar resolution.
    The current family is `known-name nested class registration on an unfit
    ClassNode` plus the lack of a class-source repair/fallback path in
    `register_class_with_name`; the first observable explosion happens when
    `register_concrete_class` reads `IncludeNode.target` through
    `resolve_path_like_name_in_arena`
- **Fresh nested-generic class-ivar reducer (2026-03-26, current session)**:
  - the post-`541e3d54` trust-enabled stage3 follower is now reduced from
    `src/stdlib/crystal/once.cr` to a 190-byte no-prelude carrier:
    `tmp/reduce_class_ivar_nested_generic.cr`
    ```cr
    module A
      struct Node
      end

      struct Box(T)
        def self.new
          uninitialized self
        end
      end

      struct Holder
        def initialize
          @waiting = Box(A::Node).new
        end
      end
    end
    ```
  - verified matrix:
    - `scripts/run_safe.sh ./tmp/run_reduce_class_ivar_nested_generic_stage1.sh 30 2048` -> green on `/tmp/stage1_release_29966272`
    - `scripts/run_safe.sh ./tmp/run_reduce_class_ivar_nested_generic_stage2.sh 30 2048` -> red on `/tmp/stage2_current_debug_exprtrace` with `exit 139`
  - clean trust-enabled LLDB on the tiny carrier:
    `Hash(String, Nil)#find_entry_with_index(String) ->
     Set(String)#includes? ->
     resolve_class_name_in_context ->
     resolve_path_string_in_context ->
     resolve_type_name_in_context_impl ->
     type_ref_for_name_inner ->
     infer_type_from_class_ivar_assign ->
     infer_ivars_from_expr ->
     infer_ivars_from_body ->
     register_concrete_class`
  - strongest current interpretation:
    the next live blocker is now honestly a nested-generic class-ivar type
    inference / name-resolution corridor, not the earlier empty-def
    `DefNode.return_type` metadata read
- **Fresh empty-def return-type root cause fix (2026-03-26, current session)**:
  - the trust-enabled no-prelude HIR oracle for a plain empty-def struct is now green:
    `./regression_tests/stage2_empty_def_return_type_hir_oracle.sh /tmp/stage1_release_29966272 /tmp/stage2_current_debug_exprtrace`
    -> `not reproduced: stage2 matches stage1 on empty-def return-type HIR oracle`
  - decisive pre-fix trace on the same current-source stage2 family showed the real sink directly:
    on `struct SpinLockLike; def lock; end; def unlock; end; end`,
    `register_concrete_class` logged
    `[REG_METHOD_PHASE] ... phase=after_return_field present=1`
    for `def lock` even though the method has no explicit return type
  - strongest current interpretation:
    the active blocker there was not broad AST corruption and not getter inference;
    it was a false non-nil read of `DefNode.return_type` in the class-registration
    corridor, very likely the same kind of adjacent composite-field / wrapper
    misread we have seen elsewhere in self-hosted stage2
  - verified source fix:
    `register_concrete_class` now takes explicit return-type metadata from
    `def_explicit_return_type_from_source(member, member_arena)` instead of reading
    raw `member.return_type` in that corridor
  - direct post-fix evidence on the same tiny carrier:
    `[REG_METHOD_PHASE] ... phase=after_return_field present=0`
    followed by clean `before_getter_infer -> after_getter_infer -> after_body_infer`
    for both `lock` and `unlock`
  - downstream movement is real:
    trust-enabled full `stage3 --STOP_AFTER_HIR` no longer dies in the old empty-def
    corridor; fresh LLDB now lands later in
    `Hash(String, Nil)#find_entry_with_index(String) ->
     resolve_class_name_in_context ->
     normalize_declared_type_name ->
     infer_type_from_class_ivar_assign ->
     register_concrete_class`
    while processing `src/stdlib/crystal/once.cr`
  - boundary/adversary:
    without `CRYSTAL_V2_TRUST_SLICE_ADDR=1`, full `stage3 --STOP_AFTER_HIR` still
    hits the broader `LibMachVM$Dmach_task_self` guard family first, so this fix
    closes the trust-enabled `DefNode.return_type` misread corridor, not the
    remaining guard-family blocker
- **Fresh no-prelude empty-def root-cause split (2026-03-26, current session)**:
  - the active self-hosted blocker is now reduced to a 61-byte no-prelude oracle:
    `tmp/reduce_struct_def_noprelude.cr`
    ```cr
    struct SpinLockLike
      def lock
      end

      def unlock
      end
    end
    ```
  - verified matrix (trust-enabled stage2 corridor):
    - `scripts/run_safe.sh ./tmp/run_reduce_struct_def_noprelude_stage1.sh 30 3072` -> green on `/tmp/stage1_release_29966272`
    - `scripts/run_safe.sh ./tmp/run_reduce_struct_def_noprelude.sh 30 3072` -> red on `/tmp/stage2_current_debug_exprtrace` with `STUB CALLED: LibMachVM$Dmach_task_self`
  - clean LLDB on the same stage2 binary and carrier:
    `LibMachVM.mach_task_self -> readable_address? -> register_concrete_class -> register_class_with_name_in_current_arena -> register_class_with_name -> register_class`
  - stage2 method-phase trace narrows the live sink below arena resolution and below eager type-literal return inference:
    - `[REG_METHOD_PHASE] ... phase=after_receiver`
    - `[REG_METHOD_PHASE] ... phase=base_name`
    - `[REG_METHOD_PHASE] ... phase=after_member_arena`
    - `[REG_METHOD_PHASE] ... phase=after_type_literal inferred=(nil)`
    - crash happens before any later `after_getter_infer` / `after_body_infer` marker
  - strongest current interpretation:
    this is no longer honestly modeled as prelude noise, nested-module noise, or broad parser transport.
    The active frontier is now the first return-type fast path for a plain empty `DefNode`
    during `register_concrete_class`, likely at or immediately before `infer_getter_return_type`
    on a corrupted/self-misread `DefNode` field wrapper.
- **Fresh inline-param source-shape falsifier (2026-03-26, current session)**:
  - the old live tiny reducer `tmp/reduce_method_yield_block_arena.cr` on fresh current-source debug `/tmp/stage2_current_debug_exprtrace` is no longer honestly modeled as the same `block-body -> HIR def registration -> $IDXS$$String_Crystal::HIR::TypeRef` family
  - decisive falsifier:
    replacing the captured block-proc write
    `each_param_with_index(params) { ... local_map[name] = param_type }`
    inside `inline_block_return_type_name` / `inline_proc_return_type_name`
    with direct `while`-based helpers
    (`seed_inline_param_type_map`, `seed_inline_param_type_map_entry`)
    moves the same reducer to a different sink with no other source changes
  - verified movement:
    - with `CRYSTAL_V2_TRUST_SLICE_ADDR=1`:
      `scripts/run_safe.sh /tmp/run_reduce_method_yield_block_arena_hir_trust.sh 30 3072`
      now reds with `STUB CALLED: Int32$Haddress`
    - without that env on the same rebuilt binary:
      `env CRYSTAL_V2_STOP_AFTER_HIR=1 /tmp/stage2_current_debug_exprtrace tmp/reduce_method_yield_block_arena.cr ...`
      reds with `STUB CALLED: LibMachVM$Dmach_task_self`
  - IR evidence on `/tmp/stage2_current_debug_exprtrace.ll` shows the new sink sits in the trust/readability guard family, not in the old block-proc `Hash(String, TypeRef)#[]=` corridor:
    - trust path: `env_has?("CRYSTAL_V2_TRUST_SLICE_ADDR") -> Bool#to_unsafe -> Int32#address`
    - no-trust path: `readable_address? -> LibMachVM.mach_task_self`
  - strongest current interpretation:
    the newly exposed live family is `safe_str_guard` / `safe_slice_to_string` / readability probing, likely a narrower value-slot / local access corruption around `Bool` trust flags and later `Slice` reads, not broad AST/arena corruption
  - next falsifier:
    move trust-flag acquisition after the first raw/ptr/addr reads in `safe_str_guard` and `safe_slice_to_string`; if the sink moves again, the real root cause is the guard-local value-slot corridor, not the guard policy itself
- **Fresh block-body handoff falsifier (2026-03-26, current session)**:
  - the current tiny block-body frontier is no longer honestly modeled as parser or `ParsedUnit` transport corruption
  - decisive falsifier on fresh current-source debug `/tmp/stage2_current_debug_exprtrace`:
    - `tmp/reduce_toplevel_block_call.cr` keeps `BlockNode.body` stable at every parser/CLI boundary we can observe:
      `parse_program_roots_wrapper`, `parse_file_recursive_after_parse`,
      `parse_file_recursive_after_append`, `top_level_collection_entry`, and even
      `pass2_before_register_def` all log the same `block=2 size=1 first=1`
    - only after entering HIR def registration does the same reducer flip into the
      old self-cycle shape:
      `expr_subtree_matches_arena?` reads `BlockNode.body idx=0 expr=3`
  - the corresponding bare-root carrier `tmp/reduce_bare_block_call.cr` also stays
    clean through `parse_file_recursive_after_parse/append` and
    `top_level_collection_entry`, then crashes later in `lower_main`
  - strongest current interpretation:
    the old broad model “parser/`ParsedUnit`/CLI handoff overlap” is now stale for
    the live blocker; the first verified corruption boundary sits inside the HIR
    consumer corridor, between CLI pass2 setup and the first
    `register_function` / `arena_fits_def?` / `expr_subtree_matches_arena?`
    walk
- **Fresh nested-module def reparse root cause fix (2026-03-26, current session)**:
  - the old `LM-246` blocker was real but narrower than “nested-module block-yield arena-fit” in general: the tiny carrier
    `module A; module B; extend self; def exec(flag, &); yield; end; end; end`
    only stayed red while nested-module registration canonicalized a snippet-reparsed `DefNode`
  - decisive falsifier:
    a runtime-only bypass of nested-module `reparse_def_from_source` turned that tiny carrier from `stage1 green / stage2 red` into `stage1 green / stage2 green` with no other changes
  - verified source fix:
    nested-module PASS-2 registration now keeps the original `DefNode` anchored to its original arena instead of storing the snippet-reparsed `DefNode` as the canonical function entry
  - verified regression signal:
    `bash regression_tests/stage2_nested_module_block_yield_hir_repro.sh /tmp/stage1_release_29966272 /tmp/stage2_current_debug_skipnestedreparse`
    => `not reproduced: stage2 succeeded on nested-module block-yield HIR repro`
  - downstream movement is real but incomplete:
    full `stage3 --STOP_AFTER_HIR` on `/tmp/stage2_current_debug_skipnestedreparse` still reds, but the stack has moved off the old `NodeSlot#node -> AstArena#[] -> register_module_with_name` sink and now lands in
    `expr_id_list_matches_arena -> body_subtrees_match_arena -> arena_fits_def -> registration_member_arena_for -> register_nested_module`
  - strongest current interpretation:
    the closed family was “canonicalizing snippet-reparsed nested-module defs”; the new live family is a later nested-module `arena_fits_def` / `expr_id_list_matches_arena` sink on a different carrier
- **Fresh lib-class name guard root cause fix (2026-03-26, current session)**:
  - after commit `654ed48c`, full `stage3 --STOP_AFTER_HIR` on `/tmp/stage2_current_debug_modulefix_retest` still hit the old lib corridor, but the reducer matrix was now narrower than the historical `LM-240` model:
    - `struct PthreadAttrT; x : Int32; end` was `stage1 green / stage2 green`
    - `lib LibC; struct PthreadAttrT; x : Int32; end; end` stayed `stage1 green / stage2 red`
  - phase trace on the tiny lib carrier proved the crash was not in `@lib_structs.add` or later class registration setup: it reached `register_lib_member(ClassNode)` `phase=class_before_name` and died before `phase=class_after_guard`
  - the decisive falsifier was runtime-only: `CRYSTAL_V2_SKIP_LIB_CLASS_NAME_GUARD=1` turned the tiny lib carrier green immediately, which localized the real blocker to `safe_str_guard(node.name, "return")` in the lib-class path
  - the verified source fix now removes that crashy guard from `register_lib_member(ClassNode)` and reuses `class_name_from_node(node)` for source-aware header recovery
  - new oracle:
    - `bash regression_tests/stage2_lib_struct_name_guard_hir_oracle.sh /tmp/stage1_release_29966272 /tmp/stage2_current_debug_libnamefix`
    - result: `not reproduced: stage2 matches stage1 on lib-struct name-guard HIR oracle`
  - downstream movement is real:
    - tiny lib carrier is green on `/tmp/stage2_current_debug_libnamefix`
    - full `stage3 --STOP_AFTER_HIR` moved off the old `Int32#address -> register_lib_member -> with_resolved_body_arena -> register_lib_body -> register_lib` sink and now crashes later in a nested-module/block-body arena-fit family
- **Fresh nested-module block-yield frontier (2026-03-26, current session)**:
  - after the lib-class name fix, the new honest tiny carrier is:
    - `module A; module B; extend self; def exec(flag, &); yield; end; end; end`
  - verified matrix:
    - `stage1` (`/tmp/stage1_release_29966272`) + `CRYSTAL_V2_STOP_AFTER_HIR=1` -> green
    - current self-hosted `stage2` (`/tmp/stage2_current_debug_libnamefix`) + `CRYSTAL_V2_TRUST_SLICE_ADDR=1 CRYSTAL_V2_STOP_AFTER_HIR=1` -> `exit 139`
  - important reduction result:
    - `run_initializer(flag) { yield }` is **not** required
    - `protected` is **not** required
    - the smallest currently verified red shape is nested module + `extend self` + class-method block arg + bare `yield`
  - tiny trace on that carrier shows nested-module registration itself finishes and then crashes:
    - last clean markers are `phase=def_after_yield_tail` and `phase=after_pass2`
  - tiny LLDB and full-stage3 LLDB together suggest the next root-cause family is no longer lib-specific:
    - tiny carrier: `NodeSlot#node -> AstArena#[] -> register_module_with_name`
    - full stage3: `expr_id_list_matches_arena -> body_subtrees_match_arena -> arena_fits_def -> registration_member_arena_for -> register_nested_module`
  - strongest current interpretation:
    - this is a nested-module method body arena-fit / block-yield family, not the old lib name-slice blocker and not the earlier simple nested-module `extend self` carrier already closed by `654ed48c`
- **Fresh nested-module extend target root cause split (2026-03-26, current session)**:
  - the previous “nested module def registration tail” model was too broad for the live self-hosted blocker
  - clean no-prelude reducers split the family sharply:
    - `module A; module B; extend self; end; end` was `stage1 green / stage2 red`
    - `module A; module B; extend M; end; end` with a local helper module was also `stage1 green / stage2 red`
    - `module A; module B; def self.x : Int32; 1; end; end; end` stayed `stage1 green / stage2 green`
  - that matrix falsifies generic nested-module method registration as the immediate sink and pins the active root cause to nested-module `ExtendNode` target handling inside `register_module_with_name`, before any later function-registration tail
  - the verified fix is narrow and source-safe: nested module/module-body `extend` scanning now classifies `member.target` through `extend_target_is_self_in_arena?` instead of directly reading `IdentifierNode#name` in the fragile hot path
  - verified result:
    - current-source clean debug candidate keeps `reduce_nested_module_extend_self_only.cr`, `reduce_nested_module_extend_other.cr`, `reduce_nested_module_def_arena.cr`, and `reduce_nested_module_def_self_receiver.cr` all green under `CRYSTAL_V2_STOP_AFTER_HIR=1 --release --no-prelude --no-ast-cache`
    - stage1-vs-stage2 HIR now matches on the new oracle `regression_tests/stage2_nested_module_extend_target_hir_oracle.sh`
  - environment note:
    - the oracle still needs `CRYSTAL_V2_TRUST_SLICE_ADDR=1` on stage2 to bypass the older Mach-readable-address guard family (`LibMachVM.mach_task_self`); that is a pre-existing independent noise source, not part of this fix
- **Fresh owner-namespace include root cause split (2026-03-26, current session)**:
  - the old self-hosted `String$Dbytesize` abort on nested include resolution was real and narrower than the surrounding `include` logic: the tiny no-prelude carrier `tmp/reduce_nested_include_owner_ns.cr` (`module A; module M; ...; struct C; include M; ...; end; end`) is `stage1 green / stage2 red` on the older debug probe, and `lldb` pins it to `resolve_module_name_in_owner_namespaces_impl -> String$Dbytesize`
  - a local inline owner-namespace scan inside `register_module_instance_methods_for` is a strong falsifier, not a guess: the same tiny carrier turns green on `/tmp/stage2_current_debug_nsinline`, and full `stage3 --release --STOP_AFTER_HIR` moves off the old `String$Dbytesize` sink into a later HIR corridor
  - strongest current interpretation: this was a helper-call-boundary bug on `String` arguments in the owner-namespace resolver, not a generic include/path-resolution logic failure
- **Fresh nested-module def registration frontier (2026-03-26, current session)**:
  - the new post-inline blocker is now reduced to `tmp/reduce_nested_module_def_arena.cr`:
    `module A; module B; extend self; def x : Int32; 1; end; end; end`
    which is `stage1 green / self-hosted stage2 red`
  - traces on `/tmp/stage2_current_debug_nestedposttrace` falsify several earlier hypotheses for this carrier: it reaches `def_after_name`, `def_after_member_arena`, `def_after_namespace`, `def_after_yield_scan`, `def_after_full_name`, and `def_after_register_type`
  - source-derived return-type recovery is now verified as a real sub-fix inside the same corridor: on the latest probe, `DefNode.return_type` no longer degrades to an empty string; the trace now shows `rt=Int32` on the tiny oracle
  - with `DEBUG_REGISTER_DEF_RAW=1`, the same carrier also reaches the first `set_function_def_entry("A::B.x", ...)` and a second `def_contains_yield?` pass before aborting, so the live frontier has moved below raw method-name, member-arena, and raw return-type transport
  - this note is now partially stale:
    the old carrier remains useful, but the immediate crash on that reducer is no longer modeled as a post-`register_function_type` tail; the stronger current root cause is the earlier nested-module `ExtendNode` target classification bug recorded above
- **Branch**: `bootstrap-benchmark` (merged `inline-structs`)
- **Regression baseline**: last broadly re-verified count from the earlier inline-struct phase was `87/88 + 18/20`; later parser/HIR/bootstrap changes have not re-established that full baseline yet
- **Fresh macro-expr brace normalization (2026-03-26)**:
  - the strongest falsifier finally separated root cause from `time.cr` noise: on the same self-hosted probe binary, runtime `CRYSTAL_V2_DISABLE_MACRO_EXPR_BRACE_SYNTH=1` moved `trivial-root + default prelude + CRYSTAL_V2_STOP_AFTER_PARSE=1` from `2/15` failures to `0/15`, and full `src/crystal_v2.cr --release + CRYSTAL_V2_STOP_AFTER_PARSE=1` from `1/5` to `0/5`
  - that localized one real parse-only crash family to `src/compiler/frontend/parser.cr` `Parser#current_token`, specifically the hot-path brace synthesis that mutated `Array(Token)` with `@tokens.insert(...)` after preload
  - the actual fix now pre-normalizes brace-like `{{ ... }}` pairs once after token preload and removes the hot-path token-array mutation entirely; fresh self-hosted release `/tmp/stage2_release_macrobrace_normalized` still builds green from `/tmp/stage1_release_29966272` in `[EXIT: 0] after ~167s`
  - downstream signal moved exactly as expected: `bash regression_tests/stage2_time_parse_repro.sh /tmp/stage2_release_macrobrace_normalized` is now green (`not reproduced ... all 5 attempts`), and the old abstract-macro char oracle still stays green through `HIR`/`MIR` and only reaches the pre-existing `ll` diff
  - this does **not** close the whole parse frontier: custom repeated stats on the fixed binary improved but remain non-zero (`trivial-root + default prelude = 1/15`, full `src/crystal_v2.cr --release = 1/5`), and the surviving full-project parse-only crash moved later from the old `time/unicode` corridor into `src/compiler/semantic/types/*` (latest observed failure at `array_type.cr` between `file exists, reading` and `read done`)
- **Fresh absolute generic header leaf-name fix (2026-03-26)**:
  - the new `Crystal::Crystal` frontier is now root-caused, not guessed: it was not a corrupted `node.name` slice and not a `Set(String)` primary failure. A narrow debug self-hosted probe on `src/stdlib/crystal/small_deque.cr --release --STOP_AFTER_HIR` showed `class_name_from_node` falling back to source text for absolute-path headers like `struct Crystal::PointerLinkedList(T)` and extracting only the first namespace segment (`Crystal`) because `definition_name_from_header_text` stopped at the first `:`
  - that made generic accessor registration synthesize `Crystal::Crystal` instead of `Crystal::PointerLinkedList`, which then fed the later `resolve_class_name_in_context` / `Hash(String, Nil)` crash corridor
  - the verified fix is leaf-aware source recovery for class/struct/enum headers only: `class_name_from_leading_snippet_header`, `class_name_from_node`, and `enum_name_from_node` now use `definition_leaf_name_from_header_text`, while `module_name_from_node` deliberately stays on wrapper/head extraction
  - new fast oracle:
    `bash regression_tests/stage2_absolute_generic_header_leaf_hir_oracle.sh /tmp/stage1_release_29966272 /tmp/stage2_release_leafnamefix`
    => `not reproduced: stage2 preserves absolute generic header leaf names in HIR template registration`
  - the oracle splits the fix cleanly:
    - trusted `stage1` on `struct Crystal::PointerLinkedList(T); getter size : Int32 = 0; end` => `Crystal::PointerLinkedList`
    - old self-hosted `stage2` `/tmp/stage2_release_aliasctxguard` => `Crystal::Crystal`
    - fixed self-hosted builds (`/tmp/stage2_debug_leafnamefix`, `/tmp/stage2_release_leafnamefix`) => `Crystal::PointerLinkedList`
  - downstream movement is real but incomplete:
    - full `src/stdlib/crystal/small_deque.cr --release --STOP_AFTER_HIR` on `/tmp/stage2_release_leafnamefix` no longer logs bogus `Crystal::Crystal`; it now reaches `Crystal::PointerLinkedList`
    - full `stage3 --release --STOP_AFTER_HIR` on `/tmp/stage2_release_leafnamefix` still reds immediately after parse and remains in the later `Hash(String, Nil)#find_entry_with_index(String) -> resolve_class_name_in_context -> build_template_accessor_class_info` family
- **Fresh nested-module HIR stabilization (2026-03-26)**:
  - earlier cache-version asymmetry in `register_nested_module` was real but secondary: probe-only `bump_module_defs_cache_version` alone left the minimal no-prelude `module A::B::C` carrier red
  - the actual stage3 blocker sat in the same function's `extend_nodes = body.compact_map { ... }` corridor: under self-hosted stage2, nested-module bodies with no `ExtendNode` members could still enter `extend_nodes.each`, and `lldb` showed the crash at `register_module_class_methods_for(ext.target, ...)` via `Pointer(Void)#target`
  - replacing that one `compact_map` with the already-used manual `[] of ExtendNode` + `body.each` builder closes the minimal HIR oracle and its stdlib follower on main-tree stage2 release `/tmp/stage2_release_main_nestedfix`
  - new green oracle: `bash regression_tests/stage2_nested_module_depth3_hir_oracle.sh /tmp/stage1_release_29966272 /tmp/stage2_release_main_nestedfix`
  - downstream signal moved too: `CRYSTAL_V2_STOP_AFTER_HIR=1 /tmp/stage2_release_main_nestedfix src/stdlib/crystal/system/time.cr --release --no-prelude --no-ast-cache --emit hir ...` is now green
  - fresh release measurement: trusted `stage1` -> current main-tree `stage2 --release` is green in `[EXIT: 0] after ~169s`, `/usr/bin/time -l = 200.82s real`, output `/tmp/stage2_release_main_nestedfix`
  - stage3 no longer dies in the old nested-module HIR corridor: full-project `CRYSTAL_V2_STOP_AFTER_PARSE=1 /tmp/stage2_release_main_nestedfix src/crystal_v2.cr --release --no-ast-cache ...` is green, while the new direct parse follower is `src/stdlib/time.cr`
  - new red repro for the moved frontier: `bash regression_tests/stage2_time_parse_repro.sh /tmp/stage2_release_main_nestedfix` => `reproduced: compiler crashed before STOP_AFTER_PARSE on src/stdlib/time.cr`
- **Fresh default-arg root cause fix**:
  - `HIR::Function` was snapshotting param default literals into parallel arrays before `ast_to_hir` filled them, so omitted default args later degraded to backend zero-padding (`foo(0)`, `advance(0)`, `peek_byte(0)`) instead of their declared defaults
  - narrowed no-prelude LLVM oracle is now green on fresh stage1 release `/tmp/stage3_paramfix/stage1_release_paramfix`:
    `bash regression_tests/stage1_default_arg_padding_repro.sh /tmp/stage3_paramfix/stage1_release_paramfix`
    => `not reproduced: omitted default argument is preserved as literal 1 in LLVM IR`
  - downstream operational signal moved too: the old self-hosted comment-only lexer hang (`# hi`) is gone on fresh self-hosted release stage2 built from that stage1
- **Fresh release bootstrap measurements after default-arg fix**:
  - original compiler -> current `stage1 --release`: green in `531.39s real`, peak memory footprint `7148198032` bytes (`max resident set size 7989673984`) -> `/tmp/stage3_paramfix/stage1_release_paramfix`
  - current `stage1 --release` -> self-hosted `stage2 --release`: green in `[EXIT: 0] after ~167s` for `/tmp/stage3_paramfix/stage2_release_paramfix`
- **Fresh macro require-scan hardening**:
  - self-hosted crash in `CLI#macro_literal_require_texts` while scanning stdlib macro requires was real; raw `MacroPiece` access in the require-scan corridor is still unstable enough under self-hosted release to segfault
  - moving require-scan to raw source text via `node.span` and `macro_literal_texts_from_raw` produces a new self-hosted release candidate `/tmp/stage3_paramfix/stage2_release_macrospanfix`, green in `[EXIT: 0] after ~163s`
  - this does not clear stage3, but it does move the parse frontier forward: `stage2_primitives_parse_repro.sh` now progresses well past `primitives.cr` require processing and only fast-crashes later at `src/stdlib/enum.cr` `parse_program_roots start`
- **Fresh macro parser stabilization (release candidate `/tmp/stage2_release_macrospan_refactor`)**:
  - `parse_macro_body` no longer stores hot-loop text buffering state in `Token?` / `{Token, Bool}` tuples; the new candidate tracks text-buffer boundaries with `Span` instead
  - this removes the old self-hosted release crash class on the reduced `abstract struct + {% begin %} + each_char do |char| next if char == 'x' end` oracle: the old candidate `/tmp/stage3_paramfix/stage2_release_macrospanfix` reproducibly died with `exit 139`, while `/tmp/stage2_release_macrospan_refactor` now fails deterministically with `error: Index out of bounds`
  - downstream signal moved too: isolated `src/stdlib/enum.cr --release --no-prelude --no-ast-cache` parse-only now hits the same deterministic `Index out of bounds` instead of a fast segfault
  - the new narrowed matrix is:
    - green on stage2 candidate: `struct` control with the same `% begin` char loop
    - green on stage2 candidate: `abstract struct` with `% begin` + `buffer = uninitialized UInt8[{{ 1 + 1 }}]`
    - green on stage2 candidate: `struct` with both `{{ 1 + 1 }}` and the `char` loop inside `% begin`
    - red on stage2 candidate, green on stage1: `abstract struct` + `% begin` + `do/end` char loop (`regression_tests/stage2_abstract_macro_char_parse_repro.sh`)
  - fresh 2026-03-25 reducer pass narrows the same cluster much further:
    - red on stage2 candidate, green on stage1 and stage2 struct control: `abstract struct` + `% begin` + bare char literal `'x'` (`regression_tests/stage2_abstract_macro_char_literal_parse_repro.sh`)
    - `each_char`, `do/end`, and `next if` are no longer required to reproduce; they were symptom carriers, not the minimal cause
    - instrumentation on a clean `HEAD` diagnostic stage2 shows `lex_char` itself reaches a valid token (`kind=Char`, `offs=58..61`, `size=1`) before returning, while parser-side diagnostics later see the corresponding preloaded token slot corrupted or crash when touching it
    - the strongest current hypothesis is no longer "macro body nesting logic"; it is a parser-side token transport/storage corruption corridor for char literals after `lex_char` returns, likely in the same family as earlier value-type wrapper failures (`Token?` / `ExprId` / `MacroPiece`)
  - fresh 2026-03-25 clean-head falsifiers sharpen the same corridor further:
    - `DEBUG_CHAR_FULL_SLICE=1` does not move the real blocker at all on the clean parse-only path; both baseline and full-slice variants still hit the same controlled `error: Index out of bounds`
    - `DEBUG_CHAR_SENTINEL=1` also does not move the clean blocker; replacing `Token::Kind::Char` with `Identifier` for the returned char token still yields the same corrupted raw slot at parser index `21`
    - removing the local `token = Token.new(...)` temporary from the simple-char branch in `lex_char` does not help either; the corrupted parser token slot remains
    - parser-side receive instrumentation narrows the corruption boundary more precisely than before: `incoming/snapshot/stored` all remain valid for token `20`, but the parser block is never entered for token `21`, so the first bad state appears before `@tokens << token` can touch the char token
    - skipping the `next_token` post-processing path for char literals (`case token.kind` / `@last_token_kind`) also does not help; the same corrupted raw token `21` survives on the clean path
    - net result: the remaining highest-probability frontier is now the `lex_char -> next_token/each_token` handoff itself, not macro-body logic, not parser root buffering, and not the parser token array store
  - fresh 2026-03-25 positive corridor test closes that parser blocker:
    - a diagnostic candidate that inlines the bare non-escape char literal fast path directly in `Lexer#next_token` flips the minimal abstract-macro reducer, the broader `each_char` reducer, and the `src/stdlib/enum.cr` parse-only follower from red to green on self-hosted stage2
    - the most precise current interpretation is no longer a generic "char token transport" failure; it is a narrower helper-return boundary bug on the simple `'x'` path through `lex_char`
    - rebuilt main-tree candidate `/tmp/stage2_release_charfix_main` keeps the reduced carrier green through parse and `src/stdlib/enum.cr` parse-only, and the new stage1-vs-stage2 oracle `regression_tests/stage2_abstract_macro_char_literal_oracle.sh` is now green at `HIR` and `MIR`
    - the same oracle still goes red in the `LLVM IR` phase on the reduced carrier because self-hosted stage2 now reaches `step5: LLVM IR generation start` and then traps before writing the `.ll` artifact; the parser blocker is gone, but a lower LLVM-generation blocker remains
  - fresh 2026-03-26 clean-head reduction shows the same family was not actually macro-specific:
    - direct self-hosted no-prelude parse-only on `src/stdlib/io.cr` is red on `/tmp/stage2_release_29966272`, and the minimal follower is now `abstract class IO; def escaped_char_probe; '\n'; end; end`; stage1 and the stage2 concrete-class control both stay green
    - the old parser/StringPool stop was still only a sink: clean trace instrumentation showed the escaped-char token slot already corrupted during parser constructor preload, before parser code ever entered the corresponding token block
    - a separate clean falsifier proved that broad processed-slice retention is not the primary fix: switching all processed token payloads to owned strings (`retain_processed_slice`) without changing the call boundary left the reducer red
  - fresh 2026-03-26 clean-head inline-only falsifier closes that remaining escaped-char parser blocker:
    - inlining the escaped-char path directly in `Lexer#next_token` while keeping the old `@processed_strings << buffer.to_slice` storage is sufficient to make the new reducer green, so the real root cause is the remaining helper-return boundary in `lex_char`, not generic slice ownership
    - new regression script `regression_tests/stage2_abstract_escaped_char_parse_repro.sh` is green on clean head with `/tmp/stage1_release_29966272` vs `/tmp/stage2_release_head_charfix`
    - the same clean-head candidate keeps `src/stdlib/io.cr --release --no-prelude --no-ast-cache` parse-only green and moves full `stage3` to `CRYSTAL_V2_STOP_AFTER_PARSE=1` green, while `CRYSTAL_V2_STOP_AFTER_HIR=1` is still red and now dies later during `src/stdlib/time.cr` parsing
- **Fresh release bootstrap measurements**:
  - original compiler -> current `stage1 --release`: green in `525.13s real` (~8m45s), peak memory footprint `7230019776` bytes (`max resident set size 8062320640`)
  - current `stage1 --release` -> self-hosted `stage2 --release`: green in `[EXIT: 0] after ~163s`, `/usr/bin/time -l = 190.31s real`, output `/tmp/stage2_release_88dfb7f6`
  - self-hosted `stage2 --release` -> `stage3 --release`: still red; `scripts/run_safe.sh ... 1200 12288` times out with no output binary after `1200s`
  - current speed comparison is only a lower bound: `stage2` compiler is at least `1200 / 525.13 ~= 2.29x` slower than stage1 on `src/crystal_v2.cr --release`, because the stage3 build did not finish inside the safe timeout
- **Fresh reduced LLVM-metadata stabilization chain (2026-03-25)**:
  - narrowed carrier `regression_tests/stage2_abstract_macro_char_literal_oracle.sh` is now a high-signal backend oracle: after the char-parser handoff fix it stays green at `HIR` and `MIR`, so remaining red behavior is purely in `LLVM IR`
  - first blocker was not `emit_primitive_binary_override`: `lldb` showed the reduced carrier trapping immediately after `emit_functions_sequential`, inside the unconditional `Time.instant - func_emit_start` timing path in `LLVMIRGenerator#generate`
  - gating that timing/logging behind `@progress` removes the old immediate `EXC_BREAKPOINT` and lets the reduced carrier advance into metadata emission
  - next blocker was `STUB CALLED: Int32$_$OR$_UInt32$H$ADD$$Int32`; `lldb` localized it to `read_string_from_table(UInt32) -> emit_type_name_table`, and normalizing the local string-table indices to `Int32` removes that union-arithmetic stub path
  - after that, the reduced carrier moved again and `lldb` localized the next crash to `llvm_c_string_escape`, specifically `str.to_slice.each` falling into `Indexable#unsafe_fetch`; rewriting the helper to walk `String#to_unsafe`/`bytesize` directly removes that segfault
  - current reduced frontier is no longer a crash class: rebuilt candidate `/tmp/stage2_release_timegate_escape` now reaches full `.ll` artifact generation on the oracle, and the remaining red signal is a deterministic stage1-vs-stage2 `ll` diff (missing type metadata/type defs and extra empty blocks), not a parser/HIR/MIR/backend abort
  - fresh 2026-03-25 late-backend root-cause split narrows that diff substantially on rebuilt `/tmp/stage2_release_meta_block_trace`:
    - the old `__crystal_main` empty-block corruption was real and was not an LLVM CFG issue; it came from self-hosted late-backend scratch-buffer transport
    - `IO::Memory#gets` on compiler-emitted function buffers was the first broken layer (`buffered_bytes=32`, `processed_lines=0` on `__crystal_main`)
    - replacing `gets` with `String#each_line` was still not sufficient; the self-hosted binary then produced multi-line pseudo-lines, so the next broken layer was high-level line splitting itself
    - manual byte scanning over `IO::Memory#to_slice` closes that corridor: new targeted oracle `regression_tests/stage2_main_block_copy_ll_oracle.sh` is green on `/tmp/stage3_paramfix/stage1_release_paramfix` vs `/tmp/stage2_release_meta_block_trace`
    - the full abstract-char backend oracle is still red, but the diff has shrunk again: `__crystal_main` now matches stage1 and the remaining reduced red is concentrated in missing type metadata/type defs (`@__crystal_type_*`, `%String`, `%Foo`)
    - strongest global pattern so far: self-hosted late backend is unstable on high-level scratch-buffer helpers (`IO::Memory#gets`, `String#each_line`, and likely `IO::Memory` text staging/append helpers), while raw byte-slice paths (`to_slice` + manual scan / direct `write`) are holding on the same reducer
- **Fresh self-hosted lexer stabilization**:
  - release candidate `/tmp/stage2_release_lexerscanfix_v4` builds green from current source via original `stage1` in `194.59s real`, `[EXIT: 0] after ~167s`
  - self-hosted `stage2 --release --no-prelude` parse-only now survives numeric literals that previously hung or blew memory in lexer preload: `1`, `1_2`, `1.5`, `1e2`, `1_f32`, `1i64`, `1u8`
  - new green regression: `regression_tests/stage2_numeric_literal_parse_repro.sh`
  - root-cause chain for this corridor:
    - `lex_number` integer scan self-looped in self-hosted release on `1\n`
    - after fixing digit scan, `lex_newline` tokenized `\n` forever without advancing
    - after fixing newline/whitespace, decimal/exponent/`_f32` paths still leaked into `lex_operator` or suffix scanning because single-byte consumes inside `lex_number`/`lex_number_suffix` were still using fragile `advance`/loop shapes
- **Fresh numeric literal stabilization**:
  - release candidate `/tmp/stage2_release_underscorefix_v7` builds green from current source via original `stage1` in `181.97s real`, `[EXIT: 0] after ~156s`
  - `HIR::Literal -> MIR::Constant` now keeps primitive numeric payloads out of the corrupted union path, so self-hosted stage2 no longer prints `const nil` / empty `const  : Int32` for reduced numeric carriers
  - `NumberNode` now normalizes underscores and numeric suffixes with a manual byte scanner instead of `gsub`/regex, fixing the last self-hosted `1_2 -> 0` parse-time regression
  - `regression_tests/stage2_numeric_literal_mir_oracle.sh` is green again on `/tmp/stage2_release_underscorefix_v7`
  - direct self-hosted HIR spot-check is green again:
    `CRYSTAL_V2_STOP_AFTER_HIR=1 /tmp/stage2_release_underscorefix_v7 --release --no-prelude --no-ast-cache --emit hir --no-link /tmp/stage2_underscore_number.cr -o /tmp/stage2_underscore_number_v7`
    now emits `literal 12 : Int32`
- **Fresh parser stabilization**: forcing `AstArena` in parser bootstrap removes the bogus self-hosted `PageArena` path (`DEBUG_ARENA_ADD` now shows sane `id=0` instead of negative PageArena ids)
- **Fresh macro parser stabilization**:
  - boxed `parse_macro_body` depth counters survive ordinary text-token iterations in self-hosted stage2
  - `macro probe(*methods)` oracle now consumes both inner `{% end %}` markers and no longer leaks extra top-level `MacroLiteral` / `Identifier` roots
- **Fresh parser stabilization**:
  - `parse_parenthesized_call` now restores `@parsing_call_args` on the ordinary return path instead of relying on the old broad outer `ensure`
  - new reduced trailing-block oracle flips old self-hosted stage2 red -> green:
    `regression_tests/stage2_parenthesized_block_call_args_repro.sh`
  - stronger downstream signal moved as well: `stage2_object_parse_noprelude_repro.sh` is now green `5/5` on the new self-hosted stage2 candidate
- **Fresh HIR stabilization**:
  - generic param recursion guard no longer crashes hashing `Pointer(UInt8)` in `type_ref_for_name_inner`
  - `CRYSTAL_V2_STOP_AFTER_HIR=1` on the macro oracle is now green and produces a deterministic stage1-vs-stage2 HIR diff instead of a segfault
- **Fresh reduced post-parse stabilization**:
  - constructor-time `Time::Instant?` init in `AstToHir` no longer self-hosted-crashes immediately after parse on the reduced trailing-block carrier
  - `Function` now stores raw parameter snapshots directly instead of a nested parameter object container
  - MIR `convert_type` now dispatches on raw `type_id` instead of `TypeRef` struct equality, removing the self-hosted `Int32 -> Type#24` regression
  - on the reduced `callargs_leak_reduced.cr` oracle, current-source `stage1` and self-hosted `stage2` now match byte-for-byte at both HIR and MIR
- **Fresh HIR analysis stabilization**:
  - `EscapeAnalyzer` and `TaintAnalyzer` no longer rely on Crystal stdlib `Hash` default-proc writes for `@users`
  - self-hosted stage2 no longer dies in `Missing hash key: 3` / `propagate_escapes` while building compiler MIR
- **Fresh LLVM nil-slot stabilization**:
  - cross-block `Cast ... : Nil` / `Cast ... : Void` values now take the default-slot-store path instead of tripping `LLVM_MISSING_VALUE`
  - the concrete failing optimizer paths were self-hosted `inttoptr ... : Nil` chains inside `Crystal::MIR::PeepholePass#run` and `Crystal::MIR::CopyPropagationPass#run`
  - new bootstrap regression script: `regression_tests/stage2_nil_slot_bootstrap_repro.sh`
- **Focused green oracles**:
  - stage2 float literal parse/FastFloat accessor stub repro is green
  - stage2 `case/when` with `Char` literals inside defs is green
  - narrow literal oracle is green (`literal 42 : Int32`, not `literal nil`)
  - full numeric MIR oracle is green again on the new self-hosted stage2 candidate (`1`, `1_2`, `1i64`, `1u8`)
  - reduced trailing-block call-args oracle is green on the new stage2 candidate
  - `src/stdlib/object.cr --release --no-prelude` parse-only repro is green `5/5` on the new stage2 candidate
  - reduced trailing-block carrier now reaches `CRYSTAL_V2_STOP_AFTER_MIR=1` on self-hosted stage2 and matches current-source stage1 MIR output
  - full self-hosted stage2 debug bootstrap now reaches deep LLVM generation without any `LLVM_MISSING_VALUE` diagnostics on the old `PeepholePass#run` / `CopyPropagationPass#run` nil-slot frontier
  - full self-hosted `stage2 --release` bootstrap is green from current `HEAD` via `/tmp/stage1_release_88dfb7f6 -> /tmp/stage2_release_88dfb7f6`
- **Focused red oracles**:
  - fresh narrowed parser oracle is still red on the new release candidate but no longer segfaults:
    `bash regression_tests/stage2_abstract_macro_char_parse_repro.sh /tmp/stage3_paramfix/stage1_release_paramfix /tmp/stage2_release_macrospan_refactor`
    => stage1 abstract control green, stage2 struct control green, stage2 abstract case red with deterministic `Index out of bounds`
  - fresh self-hosted release stage2 still fast-crashes on stdlib parse-only recursion, but the boundary has moved:
    `bash regression_tests/stage2_primitives_parse_repro.sh /tmp/stage3_paramfix/stage2_release_macrospanfix`
    now reproduces later at `src/stdlib/enum.cr` `parse_program_roots start`, instead of the older `primitives.cr` `macro_literal_require_texts` crash
  - fresh `stage3 --release` on `/tmp/stage3_paramfix/stage2_release_macrospanfix` is still red, but now fails fast in the same later stdlib corridor (`exit 139`, `0.13s real`) instead of the older `1200s` timeout class
  - tiny no-prelude self-hosted default-arg user carrier is no longer mis-lowered to `foo(0)`, but it is still not fully green on stage2 itself:
    `CRYSTAL_V2_STOP_AFTER_MIR=1 /tmp/stage3_paramfix/stage2_release_macrospanfix --release --no-prelude --no-ast-cache --emit mir --no-link /tmp/stage3_paramfix/default_arg_repro.cr -o ...`
    still aborts with `error: Index out of bounds`
  - mixed numeric `--emit hir` on self-hosted stage2 still aborts in `Printer$Dshortest$$Float64_IO` before artifact write, so float-literal HIR diffing is blocked by a separate printer stub issue
  - tiny `1\n --no-prelude --emit llvm-ir --no-link` on `/tmp/stage2_release_underscorefix_v7` still segfaults in LLVM generation after MIR succeeds; direct `lldb` now points at `Crystal::MIR::LLVMIRGenerator#emit_primitive_binary_override`
  - reduced trailing-block no-prelude carrier no longer diverges in HIR/MIR, but self-hosted stage2 still segfaults in LLVM generation when allowed past MIR on the same carrier
  - stage3 bootstrap still dies while parsing `src/stdlib/object.cr`
  - `stage2_process_executable_path_parse_repro.sh` is now flaky on the new stage2 candidate (`attempt 1 = green`, `attempt 2 = 139`)
  - full `char_toplevel` compile on self-hosted stage2 still segfaults after parse
  - full self-hosted stage2 debug bootstrap under `scripts/run_safe.sh ... 600 4096` is now killed by memory growth at `4231664KB > 4096MB` after ~293s during LLVM generation
  - self-hosted `stage2 --release` -> `stage3 --release` currently times out after `1200s` under `run_safe` with no output binary
- **Fresh root-cause matrix signal**:
  - the earlier `object-field Hash clear/reuse` interpretation was too broad. `regression_tests/stage1_hash_field_clear_repro.sh` is still a valid red symptom oracle, but clean state-only controls show that container state is not the failing invariant: both local `Hash(UInt32, String)` and object-field `Hash(UInt32, String)` stay green on `has_key?(2u32) && size == 1`, and object-field `Array(UInt32)` state control stays green too
  - the real split is lookup/equality, not `clear`: the new minimal no-IO oracle `regression_tests/stage1_hash_lookup_string_eq_repro.sh` uses plain local `h = {} of UInt32 => String; h[2u32] = "fresh"; h[2u32] == "fresh"` and reproduces on current `stage1` while the same source built by original `crystal build --release` exits `0`
  - exact `HIR` is already wrong on both the local and object-field carriers: `Hash(UInt32, String)#[]$UInt32` returns `Union String | UInt32`, and the caller lowers `== "fresh"` as `UInt32#==$Int8`; this is a type/lowering drift before LLVM, not merely a backend runtime glitch
  - the older `undefined @Crystal$CCHasher$Hpermute$$UInt64` note is stale on the narrowed no-clear carriers and should not drive the next branch until it is re-derived on a minimal reproducer
  - the leading global hypothesis is now generic `Hash#[]` return-type / method-dispatch corruption, which is a better match for compiler-side map lookups than the earlier object-field-only theory
- **Fresh enum-dispatch cluster split (2026-03-26)**:
  - the new minimal runtime oracle for a bare local enum instance method (`enum Kind ...; Kind::V16.primitive?`) does **not** fail by returning a wrong boolean; `stage1 --release --no-prelude` lowers it to `Int32#primitive?` already in `HIR`/`MIR`, and the compiled binary aborts with `STUB CALLED: Int32#primitive?`
  - this is a real upstream method-resolution bug, but it is **not** the whole `TypeKind` story: a getter-backed carrier (`Box.new(Kind::V16).kind.primitive?`) is green on trusted `stage1` in both `HIR` (`Kind#primitive?`, not `Int32#primitive?`) and runtime
  - the same getter-backed carrier stays green when stress-tested with a namespaced enum (`M::Kind`), with `24` enum variants (matching `MIR::TypeKind` cardinality), and with a duplicate short-name collision (`A::TypeKind` + `B::TypeKind` in the same file); those branches are now falsified and should not be retried blindly
  - therefore the self-hosted backend symptom `type.kind.primitive? => true` for `Reference/Struct` is **not** explained by generic accessor loss, generic namespaced-enum dispatch, generic short-name `TypeKind` collisions, or a simple enum-size threshold
  - a second enum bug is independent and lower-confidence but verified as separate: self-hosted `stage2` on a fresh local enum carrier (`enum Kind ...`) segfaults before `HIR` in `AstToHir#resolve_enum_member_value` via `register_enum_with_name_in_current_arena`, so the enum-registration crash and the stage1 bare-enum dispatch drift should be tracked as different corridors unless a shared invariant is later proven
  - fresh 2026-03-26 root cause fix: `resolve_method_call` was receiving the correct bare-enum owner via `@enum_value_types[receiver_id]`, but then immediately clobbered it with `get_type_name_from_ref(receiver_type)` (`Int32`), and the method-resolution cache key also ignored the enum owner entirely
  - current debug stage1 candidate `/tmp/stage1_enum_owner_probe` now keeps the split correct on the combined cache oracle: one `Int32#primitive?` for `1.primitive?`, one `Kind#primitive?` for `Kind::V16.primitive?` (`bash regression_tests/stage1_enum_literal_owner_hir_oracle.sh /tmp/stage1_enum_owner_probe`)
- **Fresh source-fallback require dedupe root-cause split (2026-03-26)**:
  - old self-hosted `stage2` abort during full-project parse-only was not just “somewhere in macro_expander”: a new synthetic no-prelude oracle with `17` local `require "./dep_N"` entries isolates the failure to `CLI#extract_require_literals_from_source`
  - exact split:
    - trusted host stage1 green on `bash regression_tests/stage2_source_require_fallback_uniq_repro.sh /tmp/stage1_requireuniq_probe /tmp/stage2_release_enum_owner` stage1 control
    - old self-hosted stage2 red on the same oracle, even with `--no-ast-cache`, with `STUB CALLED: Set...` and `Abort (exit 134)` after `source_requires_fallback` flips true
    - this proves the first live offender is the stdlib `Array(String)#uniq` large-array path (`size > 16` -> `Set`), not only `save_require_cache`
  - current narrow fix is bootstrap-local and order-preserving: `CLI#extract_require_literals_from_source` and `CLI#save_require_cache` now use a manual stable linear dedupe helper instead of `Array#uniq`
  - verified on fresh host-built stage1 `/tmp/stage1_requireuniq_probe` and self-hosted release stage2 `/tmp/stage2_requireuniq_probe`:
    - `bash regression_tests/stage2_source_require_fallback_uniq_repro.sh /tmp/stage1_requireuniq_probe /tmp/stage2_requireuniq_probe`
      => `not reproduced: stage2 survived synthetic source-fallback require dedupe`
    - `scripts/run_safe.sh /tmp/build_stage2_requireuniq_probe.sh 1800 12288`
      => self-hosted `stage2 --release` green, `[EXIT: 0] after ~462s`
  - this closes one real bootstrap blocker but not the whole parse frontier: full-project `CRYSTAL_V2_STOP_AFTER_PARSE=1 --release --no-ast-cache` on `/tmp/stage2_requireuniq_probe` still fast-segfaults later after `src/stdlib/unicode/unicode.cr` `creating parser`, so the next blocker is now below require dedupe
- **Fresh enum-member parser handoff stabilization (2026-03-26)**:
  - old self-hosted `stage2` no-prelude HIR reducers `enum Kind; V1; V2; end` and `enum Kind; V1; V2; end; Kind::V1` were entering the bogus explicit-value path for implicit members, emitting traces like `[ENUM_MEMBER] enum=Kind member=V1 span=1 source=0 text=nil`, and then crashing downstream in `AstToHir#resolve_enum_member_value -> register_enum_with_name_in_current_arena`
  - two tempting local explanations were falsified first: changing `Frontend::EnumMember` to raw flag-backed storage was not sufficient, and changing it from `struct` to `class` was not sufficient by itself
  - the verified fix is narrower and parser-side: remove the nilable constructor boundary for enum members entirely, split `Frontend::EnumMember` into separate implicit/explicit constructors, branch in `Parser#parse_enum` without `ExprId?`/`Span?` call args, and mirror that contract in `LSP::ASTCache.read_enum_members`
  - verified on fresh host `/tmp/stage1_enumctor_probe` and self-hosted `/tmp/stage2_enumctor_probe` with the new oracle `bash regression_tests/stage2_enum_member_ctor_repro.sh /tmp/stage1_enumctor_probe /tmp/stage2_enumctor_probe`
    => `not reproduced: stage2 no longer corrupts implicit enum members on the HIR enum oracle`
  - operational signal moved with it: stage2 tiny enum reducers no longer emit bogus per-member traces and now converge to the separate generic `STUB CALLED: Crystal$CCHIR$CCTaint...Parameter` no-prelude blocker also hit by non-enum controls
  - stage3 also moved off the old enum-registration crash: fresh LLDB on `/tmp/stage2_enumctor_probe src/crystal_v2.cr --release` now stops later in `AstToHir#normalize_declared_type_name -> resolve_alias_target -> register_alias`
- **Fresh top-level alias extractor stabilization (2026-03-26)**:
  - the new alias frontier was real and narrower than the original LLDB stack suggested: tiny no-prelude carriers like `alias Foo = UInt8`, `alias Bytes = Slice(UInt8)`, and `alias HIR = Crystal::HIR` all reproduced the same self-hosted `stage2` fast `exit 139` before any codegen, while trusted `stage1` stayed green
  - source extraction itself was only partially broken: on the reduced `alias Foo = UInt8` carrier, `source_for_arena`, `slice_source_for_span`, comment stripping, and `text.index('=')` all stayed valid; the first verified bad primitive was name extraction from the left-hand side
  - specifically, self-hosted no-prelude `stage2` failed to recover `Foo` from plain ASCII `left = "alias Foo"` inside `extract_alias_name_value_from_source`: `String#rindex(' ')` failed outright, and even a reverse byte-scan fallback still produced an empty alias name on the same trace
  - the working bootstrap-local fix is grammar-driven instead of heuristic: `extract_alias_name_value_from_source` now parses alias names by fixed `alias ` / `type ` prefixes, and top-level `register_alias` always prefers the source-extracted `{alias_name, target}` pair before touching dangling `AliasNode` slices
  - verified on fresh self-hosted release `/tmp/stage2_aliasprefixfix_probe`:
    - `scripts/run_safe.sh /tmp/build_stage2_aliasprefixfix_probe.sh 1800 12288`
      => self-hosted `stage2 --release` green, `[EXIT: 0] after ~465s`
    - `bash regression_tests/stage2_alias_builtin_hir_repro.sh /tmp/stage1_enumctor_probe /tmp/stage2_aliasprefixfix_probe`
      => `not reproduced: stage2 survives the top-level alias HIR oracle past alias registration`
  - reduced operational signal moved exactly where expected: tiny no-prelude alias carriers no longer die with `exit 139` and now converge to the separate shared `STUB CALLED: Crystal$CCHIR$CCTaint...Parameter` blocker after `register_alias.after_store`
- **Fresh clean unsigned-literal MIR stabilization (2026-03-26)**:
  - the clean detached tree at `6af60757` still failed before producing a self-hosted `stage2` binary: guarded `stage1 -> stage2 --release` reached `step4: MIR lowering start` and then died with `error: Arithmetic overflow`
  - the first release backtrace was misleading and pointed near `lower_pointer_realloc`; a debug-stage1 falsifier on the same clean source localized the real culprit to `src/compiler/mir/hir_to_mir.cr:lower_literal` while lowering `%180 = literal 0 : UInt64` in `__crystal_main`
  - the verified root cause is narrower than a generic `UInt64` parse failure: unsigned MIR lowering was reading `lit.int_value.to_u64` instead of the already-carried `lit.uint_value`, so the wrong primitive cache was used on self-hosted unsigned literals
  - the new reduced single-compiler oracle `bash regression_tests/stage1_u64_literal_mir_overflow_repro.sh <compiler>` confirms the crash class directly:
    - old clean release host `/tmp/stage1_reltest_6af60757` => `reproduced: compiler overflowed before MIR artifact on the UInt64 literal carrier`
    - isolated one-line fix host `/tmp/stage1_debug_u64fix_6af60757` => `not reproduced: compiler survived the UInt64 literal MIR overflow carrier`
  - operational proof on an isolated clean worktree with only `builder.const_uint(lit.uint_value, ...)` applied is stronger than the reduced oracle alone: self-hosted `stage1 -> stage2 --debug` no longer dies in MIR, reaches `step4: MIR funcs=31221`, completes `generate(io) done`, and only then fails later in `llc` with `error: constant expression type mismatch: got type '[10 x i8]' but expected '[7 x i8]'` on `c"ptr null,\00"`
  - caveat: this commit class closes the MIR overflow blocker but does **not** fully solve unsigned-literal correctness yet; the large-`u64` no-prelude MIR oracle still zeroes `9223372036854775808u64` and `18446744073709551615u64` to `const 0 : UInt64`, so a second unsigned-literal preservation bug remains below the crash fix
- **Fresh ptr-zero string-constant normalization hardening (2026-03-26)**:
  - the new late `llc` mismatch after the unsigned-literal fix was not a second independent LLVM mystery: the smallest self-hosted carrier is just `puts "ptr 0,"`, and the new single-compiler oracle `bash regression_tests/stage1_ptr_zero_string_constant_repro.sh <compiler>` reproduces the exact same failure class on the isolated host with only the unsigned-literal fix applied
  - the verified root cause is a post-emit text-rewrite bug, not string interning and not `llvm_c_string_escape`: `emit_crystal_string_constant` computes `len = str.bytesize + 1` first, then the old global `ptr 0 -> ptr null` normalization in `emit` / `emit_raw` / `emit_toplevel` rewrote the payload bytes inside LLVM literals like `c"ptr 0,\00"` to `c"ptr null,\00"` without updating `[N x i8]`
  - that breaks a concrete backend invariant: declared LLVM string-array length must match the emitted escaped payload bytes; the reduced red witness shows the exact drift directly:
    - old isolated host `/tmp/stage1_debug_u64fix_6af60757` => `llc ... error: constant expression type mismatch: got type '[10 x i8]' but expected '[7 x i8]'`
    - offending line: `@.str.49.data = ... [7 x i8] c"ptr null,\00"`
  - the working fix is line-aware instead of global string-wide substitution: funnel `emit`, `emit_raw`, and `emit_toplevel` through `normalize_ptr_zero_line` / `normalize_ptr_zero_text`, and explicitly skip LLVM string literal payload lines (`c"..."`) so only real pointer tokens are normalized
  - verified on an isolated clean host rebuilt from the same worktree with only that normalization hunk added:
    - `bash regression_tests/stage1_ptr_zero_string_constant_repro.sh /tmp/stage1_debug_u64_ptrzero_6af60757`
      => `not reproduced: ptr-zero string literal compiles and runs correctly`
  - operational proof now matches the reducer: guarded clean `stage1 -> stage2 --debug` with the isolated patched host `/tmp/stage1_debug_u64_ptrzero_6af60757` no longer dies in `llc`, produces `/tmp/stage2_debug_u64_ptrzero_6af60757`, and exits `0` after `~403s`
- **Current frontier**: stage3 bootstrap is still the top operational blocker. After the absolute-header leaf-name fix, the earliest verified self-hosted red point is again the later HIR resolver crash:
  - full `stage3 --release --STOP_AFTER_HIR` on `/tmp/stage2_release_leafnamefix` still fast-segfaults after `parse done arenas=188`
  - LLDB on the fixed release candidate now shows the same downstream stack without the old bogus `Crystal::Crystal` carrier:
    `Hash(String, Nil)#find_entry_with_index(String) -> AstToHir#resolve_class_name_in_context -> resolve_path_string_in_context -> resolve_type_name_in_context_impl -> type_ref_for_name_inner -> build_template_accessor_class_info -> register_class_with_name_in_current_arena`
  - the practical reduced follower for the next round is still `src/stdlib/crystal/small_deque.cr --release --STOP_AFTER_HIR`, but its template stream now starts with the corrected `Crystal::PointerLinkedList`, so the next investigation should focus on which `Set(String)` / `Hash(String, Nil)` inside `resolve_class_name_in_context` is still null/corrupted after name recovery
  - older backend-only frontier notes still apply below this HIR blocker: tiny self-hosted `--emit llvm-ir --no-link` can still crash in `emit_primitive_binary_override`, and float-literal HIR printing still trips the separate `Printer$Dshortest$$Float64_IO` stub
  - updated frontier after the macro-span + macro-body span-tracking fixes:
    `stage2 --release -> stage3 --release` no longer sits at the old crash-class frontier; the remaining reduced parser blocker is now `abstract struct + {% begin %} + do/end char loop`, and stdlib `enum.cr` parse-only now fails with the same controlled `Index out of bounds` class instead of a segfault
  - updated frontier after the enum-member constructor fix:
    the old self-hosted stage3 stop in `resolve_enum_member_value -> register_enum_with_name_in_current_arena` is closed; the next correctness reducer to carve out is now the alias corridor `AstToHir#normalize_declared_type_name -> resolve_alias_target -> register_alias`, preferably with a tiny no-prelude oracle before re-running full stage3 timing
  - updated frontier after the top-level alias extractor fix:
    the alias-specific `register_alias` segfault on tiny no-prelude carriers is closed; the next reduced stop on those carriers is the shared `HIR::Taint << Parameter` abort, while full operational `stage2 --release` stays green and is ready for another `stage2 -> stage3` measurement pass
  - updated frontier after the clean unsigned-literal MIR fix:
    the first clean `stage1 -> stage2` failure is no longer the old MIR `Arithmetic overflow`; the next clean bootstrap blocker is now late LLVM/llc string-constant emission, currently reproducing as `constant expression type mismatch` on `c"ptr null,\00"` after `generate(io) done`
  - updated frontier after the ptr-zero string-constant hardening:
    the late `c"ptr null,\00"` length-mismatch class is now reduced and operationally fixed for clean `stage1 -> stage2 --debug`; the next useful operational checks are clean `stage1 -> stage2 --release` and then `stage2 -> stage3`, to see which frontier remains once this backend payload-corruption family is removed
  - updated frontier after the fresh clean release bootstrap checkpoint:
    detached `HEAD` `29966272` now gives clean `stage1 --release` green (`/tmp/stage1_release_29966272`, `546.50s real`, peak RSS `~8.12 GB`) and clean `stage2 --release` green (`/tmp/stage2_release_29966272`, `[EXIT: 0] after ~173s`), so stage2 is currently about `546.50 / 173 ≈ 3.16x` faster than stage1 on `src/crystal_v2.cr --release`
  - updated frontier after the fresh clean release bootstrap checkpoint:
    `stage2 -> stage3 --release` is still red, but no longer in MIR/LLVM: guarded `stage3` now dies at `[EXIT: 139] after ~2.34s`, `CRYSTAL_V2_STOP_AFTER_PARSE=1` is green, and `CRYSTAL_V2_STOP_AFTER_HIR=1` is red, so the active blocker is now in the parse/HIR corridor before MIR
  - updated frontier after the parse-stderr falsifier:
    a temporary clean-worktree gate that removed parse-phase `STDERR.puts/flush` from `CLI#parse_file_recursive` changed the stage3 failure shape but did not fix it; with that noise removed, LLDB on the new self-hosted compiler localizes the residual crash earlier and more cleanly to `libsystem_platform::_platform_memmove -> Frontend::StringPool#intern -> Frontend::Parser#parse_prefix`, so the strongest current root-cause cluster is parser/StringPool slice transport, not the old event-loop write path
  - updated frontier after the escaped-char `lex_char` handoff fix:
    the old clean stage3 parse blocker in `src/stdlib/io.cr` is closed; clean self-hosted stage2 now keeps `CRYSTAL_V2_STOP_AFTER_PARSE=1` green on `src/crystal_v2.cr --release`, and the next reducer needs to target the later `CRYSTAL_V2_STOP_AFTER_HIR=1` crash that currently reaches `src/stdlib/time.cr`
  - updated frontier after restoring raw `HIR::Function` param storage:
    the old `Taint << Parameter` abort in `HIR::Function#add_param` is closed again; `regression_tests/stage2_main_param_mir_oracle.sh` is red on `/tmp/stage2_release_head_charfix` and green on `/tmp/stage2_release_head_charfix_paramraw`, and the reduced `src/stdlib/time.cr --release --no-prelude --no-ast-cache` `CRYSTAL_V2_STOP_AFTER_HIR=1` carrier now moves from that abort to a deterministic `error: Index out of bounds`
- **Fresh Quadrumvirate synthesis (2026-03-26 late)**:
  - active contradiction ledger:
    - **refuted**: `time.cr` itself as the primary root cause; repeated reducers kept moving the stop while the same carriers moved with parser/storage fixes
    - **refuted**: macro-only explanation for the char/escaped-char family; both abstract-macro and plain `abstract class IO ... '\n'` reducers fell to the same `lex_char` handoff family
    - **refuted**: `NodeSlot` / `Reference -> Node` as the immediate cause of the tiny HIR blocker `def x; 1; end; y = x`; new arena diagnostics show the same `IdentifierNode` survives add/fetch on both raw and typed paths with stable slice-object pointer and valid `ptr/size=1`
    - **refuted**: `IdentifierNode#name` getter boundary as the immediate cause of that same reducer; internal `@name` and getter-return diagnostics stay identical on the arena side
    - **refuted**: the old `(nil)` names in `lower_main` as proof of true AST corruption; they are now better explained as a later reader/validator false negative
  - strongest new verified split on the tiny no-prelude HIR oracle `def x; 1; end; y = x`:
    - baseline self-hosted debug stage2: `MAIN_KIND_DEBUG` prints `target/value = (nil)` and later dies in the old `Index out of bounds` class
    - the same binary with `CRYSTAL_V2_TRUST_SLICE_ADDR=1` flips `MAIN_KIND_DEBUG` to real names `target=y value=x`, then dies later with `exit 139`
    - this proves the first visible failure was not a missing identifier payload at all; it was the HIR-side slice reader/validator (`safe_slice_to_string` + readable-address guard) rejecting a slice that the AST-side diagnostics still see as structurally valid
    - with `CRYSTAL_V2_TRUST_SLICE_ADDR=1` plus `DEBUG_IDENT_RESOLVE=1`, `lower_identifier` now reaches `name=x` but still reports `has_def=0 has_type=0 has_base=0` before crashing
    - `CRYSTAL2_COLLECT_TRACE=1` on the same run proves the top-level `DefNode` is still present during CLI collection (`expr=1 kind=36`), so the next live sink is earlier than identifier lookup and later than AST collection: top-level def name ingestion / registration into `@function_defs`
  - global root-cause clusters from the accumulated landmarks:
    - **cluster A: composite value boundary corruption**. Verified members: `lex_char` helper-return, escaped-char helper-return, enum-member nilable ctor, synthetic `HIR::Function` param container, `ArenaLike` / tuple / wrapper transport, `Array(TypedNode)` conditional init. Reusable fix shape: inline construction at the callsite, split nilable/default-arg constructors, store raw snapshots or reference wrappers, avoid by-value relocation of composite structs.
    - **cluster B: non-bootstrap-safe convenience helpers over composite data**. Verified members: `Array#uniq -> Set`, `compact_map`, hot-path `@tokens.insert`, `IO::Memory#gets`, `String#each_line`, `gsub`/regex number cleanup, `String#rindex` alias parsing. Reusable fix shape: manual byte scans, linear dedupe, grammar-driven source parsing, pre-normalize once instead of mutating hot growable buffers.
    - **cluster C: representation-contract mismatches**. Verified members: raw-pointer union ABI, unsigned literal cache mixup, ptr-zero text rewrite after string length computation, enum-owner cache key clobber, function param storage drift. Reusable fix shape: make the representation invariant explicit and avoid post-hoc rewrites that assume the wrong storage model.
    - **cluster D: name/slice ingestion reliability**. Verified members: StringPool owning-canonical-string fix, absolute-header leaf-name parsing, alias prefix extraction, and now the new `safe_slice_to_string` false-negative + missing top-level def registration family. Reusable fix shape: prefer grammar/source-derived extraction or minimal raw/null/range checks over heavyweight guard logic when the data is already structurally valid.
  - next root-cause-oriented move:
    - do **not** spend another branch on `lower_assign` / `lower_call` / local HIR patches for the tiny reducer
    - instead, instrument the def-registration path (`CLI def_nodes -> AstToHir#register_function`) under `CRYSTAL_V2_TRUST_SLICE_ADDR=1` and compare `DefNode.name` readback with the already-verified valid `IdentifierNode.name` carrier
    - if `DefNode.name` fails only through `safe_slice_to_string`, replace the current Mach-readable-address dependency in the hot name-ingestion path with a lighter bootstrap-safe contract (raw null/range + ptr/size sanity), then re-check both the tiny reducer and the broader `small_deque` / stage3 HIR followers
## VERIFIED: Fix `ptr 0` → `ptr null` in stage2 LLC

### Done:
- `emit_select`: normalizes ptr 0 → ptr null ✓
- `emit` helper: gsub normalization ✓
- `emit_raw`: gsub normalization ✓
- Worker temp file output (IO.copy): normalization ✓
- Parent output (IO.copy): normalization ✓
- Line-aware normalization skips LLVM string constants like `c"ptr 0,\00"` ✓

### Test:
```bash
crystal build src/crystal_v2.cr -o bin/crystal_v2 --error-trace
bin/crystal_v2 src/crystal_v2.cr -o /tmp/crystal_v2_s2
# Should compile without LLC error
```

If `ptr 0` still appears, check `emit_toplevel` (@output << s at line ~2571).

## VERIFIED: Test Stage2 Oracle

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

## NEXT: Fresh Release Bootstrap + Benchmark

1. Explain why self-hosted release stage2 still throws `Index out of bounds` specifically on `abstract struct + {% begin %} + do/end char loop` while the `struct` control and `abstract struct + {{ 1 + 1 }}` controls are green on `/tmp/stage2_release_macrospan_refactor`.
2. Continue from the new smallest surviving oracle instead of the older loop carrier:
   `abstract struct + {% begin %} + 'x'` (`regression_tests/stage2_abstract_macro_char_literal_parse_repro.sh`), then compare stage1 vs stage2 around the lexer/parser boundary rather than HIR/MIR first.
3. Re-test `src/stdlib/enum.cr --release --no-prelude --no-ast-cache` after each abstract-char reducer step; it is now a controlled `Index out of bounds` follower rather than a separate segfault family.
4. Localize the remaining self-hosted stage2 tiny default-arg red (`Index out of bounds` on `/tmp/stage3_paramfix/default_arg_repro.cr`) now that the old `foo(0)` mis-lowering is closed.
5. Re-run `regression_tests/stage2_nil_slot_bootstrap_repro.sh` on the next bootstrap candidate before chasing lower performance issues, so the old `LLVM_MISSING_VALUE` nil-slot bug stays closed.
6. Retry `stage3 --release` after the abstract-char / `enum.cr` parse frontier is fixed or reduced further.
7. When stage3 goes green, record the exact stage1 vs stage2 release compile-time delta for `src/crystal_v2.cr`.

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

## Fresh Frontier — 2026-03-26 (late)

Verified this turn on current-source self-hosted debug probes:

1. `DefNode.name` false-negative was real and came from the guard itself, not the AST payload.
   - In `register_function`, `safe_slice_to_string(node.name)` returned nil because
     `slice.unsafe_as(UInt64)` evaluated to `1`, while `pointerof(slice).as(UInt64*).value`
     held the valid object ref.
   - Local diagnostic fix made `register_function` recover `name=x`.

2. The next blocker was not “yield analysis” logic but a bootstrap-unsafe source-span guard.
   - Tiny oracle `def x; 1; end; y = x` proved `register_function` died in the first
     `def_contains_yield?` before `return_type/full_name/keying`.
   - Root cause: `span_fits_source?` lazily computed `line_count` and hit the direct Mach
     probe `LibMachVM.mach_vm_read_overwrite`.
   - Structural fix: precompute/store `line_count` when binding or registering arena sources
     (`bootstrap_bind_source_maps`, `set_source_for_arena`) so normal source validation no
     longer enters that late Mach path.

3. The following blocker was the same family on compiler-owned method-name strings.
   - After the line-count fix, `register_function` advanced into `set_function_def_entry`.
   - `lldb` and step markers showed the crash corridor was
     `strip_type_suffix -> parse_method_name_compact -> v2_string_readable? -> readable_address?`.
   - Two fixes moved the frontier:
     - `strip_type_suffix` now uses the direct uncached `$` stripper instead of full method-name parsing.
     - `v2_string_readable?` / `parse_method_name_compact` now use slot-raw reads via `pointerof(...)`
       plus structural range checks, and no longer VM-probe compiler-owned strings.

4. Tiny no-prelude oracle is now far beyond the old HIR blocker.
   - `/tmp/stage2_current_debug_stringfix /tmp/simple_toplevel_call_oracle.cr --no-prelude --emit hir`
     now reaches HIR, MIR, and LLVM generation.
   - It no longer aborts in the Mach/string guard family.
   - Current tiny follower is a non-crash output/open issue:
     `open: Bad address` while opening `/tmp/simple_toplevel_call_oracle_out.hir.ll`.

5. Stage3 HIR frontier moved too.
   - Self-hosted `src/crystal_v2.cr --release --no-ast-cache` with `CRYSTAL_V2_STOP_AFTER_HIR=1`
     no longer dies in the old Mach/string guard corridor.
   - New exact LLDB stack:
     `Int32#address -> AstToHir#register_lib_member -> with_resolved_body_arena -> register_lib_body -> register_lib`
   - So the live stage3 blocker is now in lib registration, not parser/StringPool and not
     compiler-owned String guard probing.

Immediate next steps:
1. Remove temporary debug markers from `ast_to_hir.cr` and isolate a clean commit that keeps only the verified guard fixes.
2. Reduce the new `register_lib_member -> Int32#address` stage3 HIR blocker to a tiny `lib` carrier.
3. Check whether the tiny `open: Bad address` follower is a real CLI/output-path bug or just a debug/oracle artifact after `--emit hir`.

## Fresh Frontier — 2026-03-26 (later)

Verified this turn on current-source self-hosted debug probes built from `/tmp/stage1_release_29966272`:

1. The old “lib registration” model was too wide.
   - Tiny reducer `lib LibC; struct PthreadAttrT; x : Int32; end; end` is red on stage2,
     but `lib LibC; struct PthreadAttrT; end; end` is green.
   - So the active blocker is not plain `register_lib_member` or empty lib struct registration;
     it requires a non-empty struct/class body.

2. The blocker is not lib-specific anymore.
   - Plain no-prelude reducer `struct PthreadAttrT; x : Int32; end` reproduces the same
     `Int32#address` abort on self-hosted stage2, while stage1 is green.
   - This falsifies the narrower hypothesis that only `@lib_structs` / C-struct handling is broken.

3. The live crash corridor is now pinned inside `register_concrete_class`.
   - LLDB on the plain struct reducer gives:
     `Int32#address -> AstToHir#register_concrete_class -> register_class_with_name_in_current_arena -> register_class_with_name`.
   - Phase tracing showed `register_concrete_class` passes:
     `after_pass0`, `after_include_extend_scan`, `after_record_constants`,
     `after_provisional_info`, `after_defined_instance_scan`,
     `after_defined_class_scan`, and reaches `before_body_loop`.

4. The first failing operation in the body loop is after raw arena fetch, before/inside visibility unwrap.
   - On `struct PthreadAttrT; x : Int32; end`, trace reaches:
     `loop_entry idx=0 expr=0`
     `after_arena_fetch idx=0 kind=CrystalV2::Compiler::Frontend::Node`
   - It crashes before `after_unwrap`, so the current strongest frontier is
     `unwrap_visibility_member_in_arena(raw_member, @arena)` (or the immediate call boundary around it),
     not `TypeDeclarationNode` lowering itself.

Immediate next steps:
1. Finish the active falsifier for `CRYSTAL_V2_SKIP_CLASS_BODY_UNWRAP=1` to check whether bypassing visibility unwrap makes the plain struct-field oracle green.
2. If it does, replace the broad helper call with a bootstrap-safe fast path for non-visibility nodes and then re-run the plain-struct and lib-struct reducers.
3. Only after that, re-run `src/crystal_v2.cr --release --no-ast-cache` with `CRYSTAL_V2_STOP_AFTER_HIR=1` and then resume stage2 -> stage3.
