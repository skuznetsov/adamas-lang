# Qualified source-call contract

Run `regression_tests/qualified_source_call_contract_repro.sh /path/to/adamas`.
Set `ORIGINAL_CRYSTAL_BIN` and `CRYSTAL_PATH` to the reference Crystal compiler
and its unchanged stdlib. The runner qualifies all original cases first, then
checks eight exact-output positives and five primary semantic rejections with
no output executable. Compiler and generated binaries use `scripts/run_safe.sh`.

The fixtures retain concrete metaclass ownership, inherited/generic method
families, operator names, abstract virtual dispatch, and the class/instance
side boundary. A virtual flag is not declaration authority. The runner also
checks that parser/internal failures cannot impersonate a semantic rejection.

This checks missing method families, not complete overload compatibility.
A separate known wrong-arity fallback can fabricate a physical body before
the final closure validator; it must be repaired at its source admission point.
Full prelude, regression-suite and bootstrap parity remain separate obligations.
