# Crystal V2 Bootstrap — TODO (Updated 2026-03-25)

## Current Status
- **Branch**: `bootstrap-benchmark` (merged `inline-structs`)
- **Regression baseline**: last broadly re-verified count from the earlier inline-struct phase was `87/88 + 18/20`; later parser/HIR/bootstrap changes have not re-established that full baseline yet
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
- **Fresh release bootstrap measurements**:
  - original compiler -> current `stage1 --release`: green in `525.13s real` (~8m45s), peak memory footprint `7230019776` bytes (`max resident set size 8062320640`)
  - current `stage1 --release` -> self-hosted `stage2 --release`: green in `[EXIT: 0] after ~163s`, `/usr/bin/time -l = 190.31s real`, output `/tmp/stage2_release_88dfb7f6`
  - self-hosted `stage2 --release` -> `stage3 --release`: still red; `scripts/run_safe.sh ... 1200 12288` times out with no output binary after `1200s`
  - current speed comparison is only a lower bound: `stage2` compiler is at least `1200 / 525.13 ~= 2.29x` slower than stage1 on `src/crystal_v2.cr --release`, because the stage3 build did not finish inside the safe timeout
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
- **Current frontier**: stage3 bootstrap is still the top operational blocker (`stage2 --release -> stage3 --release` timing out after `1200s`), but the cleanest newly reduced correctness bug is now the HIR-level `Hash(UInt32, String)#[] -> Union String | UInt32` drift. For backend-only reducers, tiny self-hosted `--emit llvm-ir --no-link` still crashes in `emit_primitive_binary_override`, while float-literal HIR printing still trips the separate `Printer$Dshortest$$Float64_IO` stub.
  - updated frontier after the macro-span + macro-body span-tracking fixes:
    `stage2 --release -> stage3 --release` no longer sits at the old crash-class frontier; the remaining reduced parser blocker is now `abstract struct + {% begin %} + do/end char loop`, and stdlib `enum.cr` parse-only now fails with the same controlled `Index out of bounds` class instead of a segfault

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
2. Reduce the remaining abstract `% begin` char-loop failure below `each_char do |char| next if char == 'x' end`, then compare stage1 vs stage2 with `--no-prelude --emit hir/mir/llvm-ir --no-link` on the smallest surviving oracle.
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
