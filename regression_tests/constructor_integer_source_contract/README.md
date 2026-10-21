# Constructor integer source contracts

Run `regression_tests/constructor_integer_source_contract_repro.sh /path/to/adamas`.
Set `ORIGINAL_CRYSTAL_BIN` and `CRYSTAL_PATH` to the matching original toolchain.
All compilation and execution use `scripts/run_safe.sh`, serially.

The original compiler runs first on every case. Eight positive programs require
exact runtime output; ten negatives require exit 1, no output binary, and the
primary argument-restriction diagnostic. An instantiation wrapper is ignored,
but a syntax error or internal compiler error cannot satisfy a negative.

The cases distinguish direct literal representability from runtime integer
domains, including signed/unsigned limits, typed and untyped constants, generic
owners, later arguments, parameters, local rebinding, and method/expression
results. A final UInt32 flow value remains legal; an Int32 value whose current
value is zero does not become a UInt32 literal.

These checks cover source contract admission, not complete allocator overload
selection, union arguments, block/named/splat shapes, LavinMQ parity or bootstrap.
