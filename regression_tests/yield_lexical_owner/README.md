# Source lexical `yield` ownership regressions

`../yield_lexical_owner_repro.sh` compares the original Crystal compiler with
Adamas for method-owned yields, Proc-literal/captured-block rejection, and
caller-block behavior across default, depth-zero, and disabled-inline modes.
The script accepts the Adamas binary as `$1` or through `ADAMAS_BIN`.

Set `RUN_PROC_NEW_YIELD_PRELUDE_ORACLE=1` to include the stdlib-backed
`Proc.new` capture case. That case is opt-in because it needs the original
stdlib, while the main matrix uses `--prelude=empty`.
