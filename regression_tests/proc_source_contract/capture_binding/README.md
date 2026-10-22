# Proc unpack collision original-first oracle

This packet separates three Crystal semantic paths that can look alike in the
AST but have different binding boundaries:

- `Proc.new` with flat and nested tuple-pattern parameters whose leaves collide
  with existing outer locals. Each body also reads a separate captured `bias`
  reference. The stream reads both leaves before construction, after
  construction but before invocation, and after invocation.
- A Proc literal whose formal parameter has the same name as an outer local,
  plus a distinct captured `bias` reference.
- An ordinary yielded block with colliding tuple-pattern leaves and a distinct
  captured reference; outer leaves are read after the call.

The explicit expected byte streams are original-derived predictions, not a
self-recorded baseline. `run.py` compiles and executes all four fixtures with
pinned Crystal first, requires exact stdout equality, and only then runs the
candidate. A pinned mismatch aborts before candidate compilation. The new
fixtures are still pending root qualification; no compiler or native program
was run to prepare this packet.

The static source distinction is visible in the pinned Crystal 1.20.1 files
listed in `manifest.json`. The normalizer rewrites unpacking into body
assignments. The ordinary `MainVisitor#visit(Block)` path separately marks
unpack leaves as block variables and excludes them from after-block flow. When
an explicit Proc.new block is consumed as a function pointer, `semantic/call.cr`
constructs a `ProcLiteral` from the already-normalized block body. That path
passes the assignments into the literal body without carrying `Block#unpacks`
metadata, so its captured-local behavior must be judged against original
Crystal. Existing original-first cases in `lavin11777_proc_complete_contract_matrix`
showed mutation for Proc.new unpack and direct ProcLiteral assignment, while an
ordinary yield-block case showed outer-local shadowing.

Run when root reserves the native slot and supplies the desired candidate:

```sh
ADAMAS_ROOT=/path/to/adamas \
ORIGINAL_CRYSTAL_BIN=/Users/sergey/Projects/Adamas/sol_help_20261012/tools/pinned_crystal_1201/crystal-1.20.1-1/bin/crystal \
PROC_UNPACK_SHADOW_OUTPUT_DIR=/absolute/new/output/path \
python3 /path/to/lavin11851_proc_unpack_shadow_oracle/run.py /path/to/candidate/bin/adamas
```

The runner uses `scripts/run_safe.sh` for each compiler and executable. Its
`--self-test` only checks runner parsing and packet files; it never invokes a
compiler.
