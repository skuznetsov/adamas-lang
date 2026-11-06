# Generated allocator target and heap-block ABI corpus

The core contains 27 cases. Its 20 positive cases require exact runtime stdout.
Its 7 negative cases require a specific semantic diagnostic, compiler exit 1,
no executable, and no crash or timeout signature. `expected.json` pins every
fixture source SHA-256. The harness qualifies all cases on original Crystal
before invoking the candidate compiler.

The cases cover stored callbacks with omitted defaults, default evaluation
exactly once, two independent allocations, initialized fields, recursive and
generic owners, and explicit block forwarding. Explicit source `self.new`
controls retain their declared value results, including class-object and union
results from a direct class call.

Both inferred and explicitly annotated terminating initializers are tested.
Their generated `.new` expressions retain the allocated instance as their
source type: an instance-return wrapper is valid, while a `NoReturn` wrapper
or an incompatible argument consumer must be rejected. A local assignment
between construction and return must preserve that same source type.

Two additional stock-valid `self.new` class/union cases remain under
`known_open/`. The default gate qualifies them on stock and explicitly excludes
them from candidate success. `RUN_KNOWN_OPEN=1` also runs them on the candidate.
The open typed-local coercion and `typeof` consumers have separate compiler
obligations and are not counted as passes here.
