# Absolute aliases in Proc annotations

Rooted `::Alias` annotations resolve from the global namespace before the
carrier type reaches a Proc signature. Lexical aliases with the same spelling
must not replace the rooted declaration. The three positive and three negative
cases cover opposite integer widths and nested lexical owners.

Run `regression_tests/proc_rooted_annotation_alias_repro.sh /path/to/adamas`.
Set `ORIGINAL_CRYSTAL_BIN` (or `ORIGINAL_CRYSTAL`) to the reference compiler.
The harness first qualifies every case with original Crystal. It then compares
exact stdout or requires semantic type rejection from Adamas. All compilers
and programs run under `scripts/run_safe.sh`; caches and binaries are removed.
