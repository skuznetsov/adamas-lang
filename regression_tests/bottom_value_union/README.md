# Bottom value union regression

Run `regression_tests/bottom_value_union_repro.sh /path/to/adamas` with
`ORIGINAL_CRYSTAL_BIN` and `ADAMAS_ROOT` set. The original compiler runs first.

A returning arm must not retain the resolved root `NoReturn` as a runtime
alternative. Four positive programs compare exact stdout (A without a newline)
and clean runtime stderr for branches, aliases, nested Tuple values, and
all-bottom aliases. Two negative programs require an ordinary source type
error, exit 1, and no executable for real union arms and a nominal
`Shadow::NoReturn`. Every compiler and program runs through `run_safe.sh`.

The no-prelude fixtures compare Int64 values directly and emit a literal Int32;
they need no checked-conversion overflow runtime. They do not cover exception
runtime behavior or bootstrap. The HIR spec separately tests repeated union
construction, binary and n-ary joins, and canonical generic arguments.
