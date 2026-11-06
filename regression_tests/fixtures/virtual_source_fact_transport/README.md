# Source argument facts across deferred and direct bodies

Run `regression_tests/virtual_source_fact_transport_repro.sh <compiler>`.
Every source is first qualified with stock Crystal using the empty prelude.
Positive programs must have identical native stdout and exit 0. Negative
programs must exit 1 with the phase-specific semantic diagnostic, leave no
executable, and avoid a compiler/resource failure.

The two main programs call inherited virtual bodies and one direct body with
the same class carrier supplied as a class object and as an instance, in both
orders. Their marker methods differ. Two extend-only class objects also test
retention of the actual module argument type.

The pair-order adversary reverses two equal-carrier arguments. The interleaved
adversary repeats class and instance calls around a second class object.
Four negatives cover an instance-only module membership passed as a class
object through direct/virtual calls, alone and inside a runtime mixed-kind
union. Every source alternative must satisfy the restriction.

These tests qualify complete positional argument facts. They do not establish
positive support for incomplete, named, transformed rest/default, or mixed-kind
body inputs, nor bootstrap or unchanged-project runtime parity.
