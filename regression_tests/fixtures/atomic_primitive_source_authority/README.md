# Atomic source-authority regression

The six runtime cases check that ordinary `Atomic::Ops` source methods keep
executing their bodies when names, arities and argument shapes resemble atomic
primitives. They cover all five operations and an ordinary overload in a family
that also contains a genuinely annotated `load` overload.

Run from an Adamas checkout:

```sh
regression_tests/atomic_primitive_source_authority_repro.sh --original-only
regression_tests/atomic_primitive_source_authority_repro.sh /absolute/path/to/adamas
```

`ORIGINAL_CRYSTAL_BIN` selects the original compiler. `ADAMAS_ROOT` can select
the checkout providing `scripts/run_safe.sh` when invoking from another directory.
The candidate gate completes the original checks first, then repeats the cases
in lazy and `ADAMAS_EAGER_MONO=1` modes. Native stdout must match the manifest
byte-for-byte and the process must exit successfully.

The genuinely annotated `fence` control checks generated LLVM IR for an actual
`fence seq_cst` instruction in each mode. Running its empty source body alone
would not distinguish a lost intrinsic from correct behavior. Its ordering enum
matches the original LLVM enum value (7).

Every compile and native run uses `scripts/run_safe.sh`. Binaries, IR, caches and
temporary files are removed on exit. The separate HIR spec
`spec/hir/atomic_primitive_authority_spec.cr` checks exact annotation selection
and invalidation after argument, target, shape and result-type changes.

This packet does not qualify full prelude, bootstrap or LavinMQ runtime parity.
