# Selected source defaults before callback slots

Run `regression_tests/source_default_block_slot_repro.sh <compiler>`.
The harness qualifies every fixture with original Crystal first, using the
empty prelude, and then requires identical native output from the candidate.
A rejected source must exit 1, emit its semantic diagnostic, and leave no
executable. Compiler crashes and resource-limit exits are not rejections.

The core `own_alias_source_slot_regression` calls a concrete generic factory
whose class-method family is still deferred. The family must be available
before defaults and callback ABI slots are bound. Registering it only during
late body lowering passes the callback as `initial_capacity` and leaves the
actual block slot null.

Controls cover explicit and omitted defaults, two default slots, a named
suffix, an aliased class method, an ordinary instance method, generated
allocators with positional and named-only defaults, and an explicit factory
forwarding to a named-only initializer (the shape used by `Time.new`). A block
cannot fill a missing required ordinary parameter.

Arithmetic fixtures use wrapping addition to remain self-contained without
the prelude's overflow handler; the test values do not overflow.
