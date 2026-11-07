# Source-kind body demand

The cache/binding example is reduced from `Log::Builder#for`. A known nullable
ABI return type does not prove that a result is an instance rather than a class
object. Bare `.value` must demand the same exact source result as `.value()`;
a nullable annotation does not replace this body-owned evidence.

The packet compares eight accepted programs and one semantic rejection with the
original Crystal compiler before testing Adamas in lazy and eager modes. The
populated-cache case observes exactly one runtime invocation. The negative case
retains a genuine class-valued result and requires the complete class/instance
return diagnostic and no executable. Empty-prelude fixtures provide their own
small supporting types; no application or standard-library files are changed.

Run `regression_tests/source_kind_body_demand_repro.sh /path/to/adamas`.
`--self-test` checks packet structure only. `--original-only` qualifies fixtures
without running Adamas. Compiler and native invocations use `scripts/run_safe.sh`.
Logs are retained; generated executables and compiler caches are removed.

The primitive controls retain a true `@[Primitive(:object_id)]` declaration
beside ordinary overloads. A bodyful sibling must execute its own body; an empty
`:Nil` sibling still needs an emitted ordinary body. Family-name registration
cannot authorize either sibling as an intrinsic. These guard the exact bodyless
intrinsic exclusion needed when result-kind demands are independent of ABI.
