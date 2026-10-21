# FFI out declaration scope

Run `regression_tests/ffi_out_lexical_scope_repro.sh /path/to/adamas` from the repository. Set `ORIGINAL_CRYSTAL_BIN` and `ORIGINAL_CRYSTAL_PATH` to compare against a specific Crystal toolchain. The defaults use Crystal from PATH and the adjacent Crystal source tree (or CRYSTAL_PATH).

All three positive and five negative cases run against the original compiler before the candidate. Successful cases must produce an executable, which is removed without running it. Negative cases require exit 1, no executable, and the case-specific primary semantic diagnostic; parser failures do not count. Every compiler runs through scripts/run_safe.sh.

The fixtures preserve the sealed 10772 matrix byte-for-byte: declaration visibility after a condition, separate sibling blocks, block-local non-escape, duplicate declarations in sibling branches, repeated declarations within one block, outer-name collision in a nested block, an ordinary repeated out, and a preexisting local. The C function is linked but never invoked. The checks cover source declaration scope, not instance-variable out, exception-handler meta-vars, or callback ABI.

The production fix separates declaration-name frames from SSA value snapshots and restores the caller frames while lowering a yielded block. Neither type restrictions nor user/stdlib source are relaxed.
