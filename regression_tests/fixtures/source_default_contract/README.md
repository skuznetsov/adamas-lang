# Source default argument contract

The exact selected Def and retained declaration arena own each default.
Materialize the expression in its declaration namespace with concrete receiver
arguments and call-local method-forall bindings. Preserve its actual source
type and class-object kind; the parameter restriction remains an upper bound.
An explicit literal conversion may create a new typed value, but admission
cannot retag a runtime expression or choose another overload after evaluation.

Supplied and defaulted source slots remain separate through replay identity.
An omitted actual can infer a method forall independently of a same-spelled
owner parameter. Earlier actuals constrain later defaults; an incompatible
later value remains rejected. NoReturn stops later evaluation and allocation,
while its own declared restriction still applies.

The original-first main gate contains 37 cases with exact stdout or strict
semantic diagnostics and no executable on rejection. The five open companions
are qualified only on original Crystal and explicitly excluded from candidate
success: callback/named forall defaults, a named owner/method-formal call, and
a kwargs call that reuses a class-valued default body for a later instance,
and an explicit invalid generic call that currently fails at a provenance guard
instead of its source restriction. They remain parity obligations.

This gate does not establish bootstrap, stock-prelude execution, or unchanged
LavinMQ runtime/upstream test parity. No standard-library or application edits
belong to this compiler contract.
