# Module source result contracts

This original-first no-prelude packet checks result source alternatives and
instance/class kinds across module methods, inline forall callbacks, typed
block calls, recursive declarations and non-local block returns. Native
positives compare exact bytes. Negative controls require the relevant Proc
or block-result diagnostic, so an incidental return-contract error cannot pass.

The completed-body controls guard against treating a declared union restriction
as the exact result. Recursive controls retain the recursive frozen restriction.
Non-local returns cover both flowing callback edges and all-escape blocks.
All compiler and generated-program executions use scripts/run_safe.sh. The
runner removes generated executables and caches and retains diagnostic logs.
