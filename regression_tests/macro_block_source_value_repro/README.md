# Source-backed macro block regression

Run `regression_tests/macro_block_source_value_repro.sh /absolute/path/to/adamas` with `ORIGINAL_CRYSTAL_BIN` set to the reference Crystal executable and `MACRO_BLOCK_OUTPUT_DIR` set to a fresh absolute output directory. All generated programs run through `scripts/run_safe.sh`.

Nine positive programs compare exact output for spawn and ordinary macros, single and multiple body expressions, absent and empty blocks, and ordinary, rest, and double-splat arguments named `block` alongside a separate callback. Five negative programs check block/body AST guard markers and invalid parameter ordering. Every reference case runs before any candidate case.

The compiler must preserve a macro block parameter's kind in the parser, carry the actual caller-owned Block AST and arena into each expander, and resolve source `spawn` through ordinary macro lookup. A missing block provider fails closed; it must never fabricate a truthy Boolean in place of the block. An ordinary parameter named `block` remains independent of `&callback`.

`run_original_first.py --self-test` validates the fixture inventory and hashes, local helper calls, and safe-run framing. It is a harness check; runtime behavior requires the original-first native run.

The parameter-order guard cases reject ordinary parameters after `**kwargs`, including after a trailing block parameter. Both compilers must reject before emitting an executable.
