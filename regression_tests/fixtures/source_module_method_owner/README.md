# Module method source-owner regressions

The 16 no-prelude fixtures distinguish a method's lexical namespace from its
source declaration owner. They cover the builtin Tuple declaration shape,
direct and included method precedence, generic includes, lexical modules,
macro-generated methods, and implicit extend-self. Two negative cases require
specific argument and return type diagnostics and no output executable.

The own-then-included-self-call Tuple case detects replacement of an already
lowered direct method with an included module method. Crystal prints `AA`.

`expected.json` records the exact fixture set, source hashes, output, and
semantic diagnostics. The runner qualifies every expectation with original
Crystal before invoking Adamas. A successful run requires both phases; this
focused set does not establish bootstrap or application test parity.

Run with `ADAMAS_ROOT_DIR`, `ORIGINAL_CRYSTAL_BIN`, and an Adamas binary argument.
Every compile and executable uses `scripts/run_safe.sh` with isolated caches
and temporary directories. Successful runs remove temporary output; failures
retain it for inspection. `ORIGINAL_ONLY=1` runs only the original phase.
