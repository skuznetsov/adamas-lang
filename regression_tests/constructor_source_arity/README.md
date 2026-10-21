# Constructor source arity

Run `regression_tests/constructor_source_arity_repro.sh /path/to/adamas`.
Set `ORIGINAL_CRYSTAL_BIN` and `CRYSTAL_PATH` to the reference compiler and its
unchanged standard library. Both compilers use an empty/no prelude. All compiler
and generated-program execution passes through `scripts/run_safe.sh`.

The main original-first matrix has 16 exact-output positives and 13 semantic
negatives. It exercises default, inherited, alias, included, generic included,
macro-generated, block and explicit factory constructors. Negative cases cover
missing/extra source arguments, bare and parenthesized zero-argument calls,
required named-only parameters, and invalid calls after a valid allocator was
already materialized. Negative success requires status 1, no executable and a
primary source constructor diagnostic; parser/internal failures cannot pass.
A separate original-first matrix checks C struct zero creation/field access,
C union zero call admission, and invalid positional constructor arguments
(two positives and two negatives). Union creation does not qualify field access.

The open_c_layout/run_original_first.py runner deliberately retains separately
reproduced, unresolved cases and is not part of the passing default wrapper.
Run it manually with the same environment and candidate argument. Crystal
passes all six cases; both parent10606 and candidate10644 fail named C struct
field initialization (zero bytes) and C union field access (missing getter or
setter). These three failures remain compiler bugs, not accepted behavior.

Physical allocator return-type entries are not source method declarations.
The arity proof enumerates only arena-owned source new/initialize definitions
and runs before default filling or allocator generation, including bare new.
It only rejects impossible positional source arities. An arity-compatible
entry still needs normal type, block, named-argument and overload selection.
Unknown arena provenance and double-splat binding cannot authorize a rejection
proof. Named and splat calls retain their existing binding paths.

This does not establish complete constructor overload order. Full prelude still
reaches the separate File constructor body/signature identity mismatch. Full
regressions, bootstrap and unchanged LavinMQ parity need separate qualification.
All temporary executable and compiler cache files are removed after each run.
