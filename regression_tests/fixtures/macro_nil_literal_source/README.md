# Explicit NilLiteral source contract

Run `regression_tests/macro_nil_literal_source_repro.sh /path/to/adamas`.
The runner qualifies the unchanged fixtures on original Crystal first, then
requires byte-exact native output and strict exit-1/no-executable type rejection.
All compiler and program executions use scripts/run_safe.sh.

Direct literal output, nil arguments, defaults, collection elements, stringify/id,
nil? and truthiness preserve NilLiteral identity. A declaration with no default retains
empty source output. Passing an explicit/defaulted nil to Int32 remains invalid.
This regression does not establish all optional reflection/Nop or unsupported
macro-method semantics.
