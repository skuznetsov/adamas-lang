# AN follow-up regression coverage

The remaining WIP contained useful coverage beyond the selected 164-script AN
manifest. This follow-up imports ten focused scripts, three fixtures, and two
HIR spec files, and adds a runner for the previously orphaned `File.join`
fixture. The eleven regression entry points pass fourteen selected cases on
the sealed AN S4 executable. The two HIR files pass seven examples on the
unchanged AN compiler source. No compiler or runtime source changes are needed.

Base revision: `60d09f3058da613574b4e8177b1c642a53a65623`.
S4 executable SHA-256:
`b9e7e330bc2c38f35c8e500f81843b09b2dbf32f885f98fe39531e19a5718ef8`.
The 1,919 source files and two runtime files retain their AN seals. The earlier
[S3/S4 fixed-point result](bootstrap_an_verification.md) therefore keeps its
original source scope; these additional cases were executed on S4 only.

| Regression entry point | Selected coverage |
| --- | --- |
| `array_clone_block_type_param_degeneration_repro.sh` | Exact `Array(String)#clone` LLVM targets and independent clone contents |
| `file_join_tuple_reduce_union_callback_repro.sh` | Real stdlib `File.join`/`Path#join`/`Tuple#reduce`, two tuple arities, both output lines and `DONE` |
| `generic_owner_method_index_repro.sh` | Two concrete Array owner families in both discovery orders; exact runtime output |
| `generic_untyped_record_return_repro.sh` | UInt32/UInt64 generic record factory return and field ownership, HIR plus runtime in both orders |
| `macro_argument_reparse_np.sh` | Macro argument source arenas with identifier, typed declaration and string controls |
| `named_receiver_source_shape_repro.sh` | Named receiver repair and the positional default control; complements existing named-only tests |
| `raw_yield_nil_callback_repro.sh` | Literal-Nil callback, Int32/Int64 tags and independent wide callee result; ternary and statement-if producers |
| `raw_yield_object_union_callback_repro.sh` | Object accumulator/result and both object/String yield orders |
| `string_builder_nul_slack_repro.sh` | Padded atomic allocation and native realloc fallback in emitted IR; 200,000 exact-capacity String builds |
| `string_wide_integer_return_repro.sh` | UInt32/UInt64/Int64 parsing, invalid input, radix and reverse discovery order |
| `untyped_callback_shape_identity_repro.sh` | Static, instance receiver and module class-method callback shapes |

Each entry runs once in its default mode. The three additional cases are
`RAW_NIL_PRODUCER_STYLE=if`, `CALLBACK_RECEIVER=1`, and `CALLBACK_MODULE=1`
for their respective scripts. The factory's HIR checks stay enabled.
The statement-if Nil producer passes AN S4; the old WIP comment calling it
known-red was removed. The two object-union compiler paths use separate caches.

The imported owner-filter HIR spec now expects the exact concrete owner when
available, matching AN's exact-owner policy. Its other examples cover template
fallback, method separators, non-generic buckets, the declared type-parameter
predicate, and fallback-key formatting. Those helper examples do not establish
general receiver-repair behavior. The generic factory HIR spec covers both
UInt32/UInt64 discovery orders and exact return, call and field types.

## Harness corrections and falsifiers

The Array clone and String NUL scripts previously used `--emit llvm-ir` and
then tried to execute a binary. That CLI mode returns before linking. Normal
compilation retains the `.ll` file and creates the runtime probe; both scripts
now require both artifacts before checking them.

The old NUL guard rejected every native allocation in `GC.malloc_atomic`.
AN emits an unrelated fixed-size bookkeeping allocation there. The revised
guard checks that the returned buffer comes from the padded allocator with the
requested size, and that allocation/reallocation actually consume the padded
values. Replay of genuine AN IR and its binary passes. Four isolated mutations
are rejected: missing slack, unused atomic slack, a different returned pointer,
and unused realloc slack. This is a check of the test guard, not execution of
modified compiler output.

The String case uses the managed full prelude. A separate experimental
full-prelude `--no-gc` invocation is rejected because that program requires GC;
it is outside this pass set. Native no-GC support retains the separately
verified no-prelude scope in `gc_aware_realloc_gating_repro.sh`.

## Commands and receipts

Run each listed shell script with the S4 path as its first argument. Additional
mode commands, with the same clean environment as the default cases:

```bash
RAW_NIL_PRODUCER_STYLE=if bash regression_tests/raw_yield_nil_callback_repro.sh "$S4"
CALLBACK_RECEIVER=1 bash regression_tests/untyped_callback_shape_identity_repro.sh "$S4"
CALLBACK_MODULE=1 bash regression_tests/untyped_callback_shape_identity_repro.sh "$S4"
scripts/run_safe.sh crystal 300 8192 spec \
  spec/hir/generic_owner_method_index_spec.cr \
  spec/hir/generic_untyped_record_return_spec.cr \
  --link-flags=-fuse-ld=/usr/bin/ld --error-trace
```

Expected signals: fourteen script cases exit 0; HIR specs report
`7 examples, 0 failures, 0 errors, 0 pending`.
The explicit linker argument in the spec command is for the verified Darwin
host. The upstream oracle was Crystal 1.21.0, LLVM 22.1.8,
`aarch64-apple-darwin25.6.0`, through a wrapper supplying that linker argument.

The recorded runs unset ambient `ADAMAS_*`, `DEBUG_*`, `CALLBACK_*`, `RAW_NIL_*`,
`EXPECT_*`, `GENERIC_RETURN_*`, `UNTYPED_CALLBACK_*`, `CRYSTAL_PATH`, and
`CRYSTAL_CACHE_DIR`, then set `ADAMAS_LLVM_CACHE=0` and the declared per-case
variables. In particular, neither expected-mismatch switch may certify a pass,
and `GENERIC_RETURN_CHECK_HIR=0` must not disable the factory guard.

Receipts live under
`/Users/sergey/Projects/Adamas/sol_help_20261012/integration_an/wip_regression_review`:
`selected_receipt.json` binds the fourteen cases, script/fixture digests and
all 56 supervised child invocations; `hir_specs.log` and `hir_specs.resources`
record the seven examples; `guard_results.json` and `guard_logs/` record the
four rejected IR mutations and positive replay. All compiler and test binary
invocations use `scripts/run_safe.sh` and exit normally. Short-lived children
have incomplete resource samples: 37 calls lack an RSS sample and 40 lack a
complete FD sample. Unknown samples are not resource bounds.

The generic arena smoke and constructor HIR addition were omitted because
stronger AN tests already cover their asserted behavior. Older compiler
variants, historical frontier notes, scratch sources, and caches remain in
the preserved original WIP. Raw-pointer struct storage remains a separate
open regression. Changes to relevant compiler/runtime source, fixtures,
scripts, toolchain or environment require the affected checks again.

## Darwin debug build follow-up

The remaining `debug.sh` change is a separate build-script correction. With
Crystal 1.21.0 on this Darwin host, the old script exits 1 in `ld64.lld` with
unresolved libc symbols. Selecting `/usr/bin/ld` via `--link-flags` produces
the debug compiler, which compiles and runs a no-prelude smoke under
`scripts/run_safe.sh`. The script applies the linker argument only on Darwin;
the non-Darwin path is untested. Commands and resource receipts are indexed by
`debug_receipt.json` in the same evidence directory. Generated debug binaries,
symbols and caches are excluded from Git.
