# Deferred setter source-result regression

The stock-first gate compares exact native output in lazy and eager candidate
modes. It covers deferred body results through ten-call chains, setter body
results distinct from their RHS, class-object inputs and results, both orders
of instance/class-object overloads sharing one ABI carrier, terminal RHS flow,
and semantic rejection of incompatible inputs and results.

Run `regression_tests/deferred_setter_source_result_repro.sh /path/to/adamas`.
Every compiler and native run uses `scripts/run_safe.sh`. The runner checks
semantic rejection status and markers, exact stdout, and safe-runner footers;
generated executables and caches are removed. Virtual receiver families are
outside this exact nonvirtual source-result gate.

`initializer_result.cr` separately protects the result of an explicit
`initialize(1)` call with one initializer definition. The former two-overload
control is preserved in `known_open/initializer_overload.cr`: Crystal accepts
it, while baseline q5942 rejects the generated allocator's outer call slots.
That constructor-demand defect is open and excluded from this setter gate.
