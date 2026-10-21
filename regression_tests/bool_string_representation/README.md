# Bool String representation

Run `regression_tests/bool_string_representation_repro.sh /path/to/adamas`.
Set `ORIGINAL_CRYSTAL_BIN` and `CRYSTAL_PATH` to the reference compiler and its
unchanged standard library. The original uses its full prelude; the candidate
uses the no-prelude builtins. All original programs must pass before candidate
compilation begins. Compiler and generated binaries use `scripts/run_safe.sh`.

The first program compares runtime String type headers against ordinary String
literals for integer, character, concatenation, interpolation and both Bool
conversions through a function parameter. It does not assume numeric type ids.
The second checks both Bool conversion contents and sizes, interpolation, and
the exact output of direct Bool writers mixed with converted String writers.
The unpatched compiler fails the first content comparison with status 11.

In no-prelude mode, literals and runtime conversion helpers use the builtin
String type id. `emit_string_constants` later sets `@string_type_id` to zero
as an emission-mode sentinel; it does not redefine the builtin type id.

Scope: the no-prelude Bool conversion representation and exercised String
producers. The full-prelude branch is unchanged. Full prelude, all String
producers, the complete regression suite, bootstrap and LavinMQ parity require
separate qualification. Parser/internal failures and unexpected runtime stderr
are failures, and temporary executables and compiler caches are removed.
