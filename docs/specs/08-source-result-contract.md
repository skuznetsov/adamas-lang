# Source Result Ownership — Frontier SDD

Status: IN_PROGRESS, 2026-11-06. The bounded return-owner implementation passes
four original-first gates against Crystal 1.22.1 (116 fixtures,
35q2635). Result-consumer precision, stock-prelude compilation, fresh bootstrap,
and unchanged LavinMQ execution and upstream test parity remain open.
The selected-default contract passes 37 main cases and ten block-slot cases
on exact-source S1 35q2760 (35q2764); five companions remain explicitly open.

This is a bounded repair to source result transport in HIR. It does not
replace the semantic architecture transition in specification 07.

## Owners and phase boundaries

An exact source definition and its retained declaration arena own a completed
method body's result facts. Each fact includes the actual source type and
whether the value is a class object. The emitted HIR function retains that
source identity together with the facts. A caller may consume them only while
the registered definition and arena still match.

A declared return restriction is an upper bound. It cannot manufacture an
actual result type or turn an instance into a class object. Its resolution
uses the declaration's namespace, concrete receiver arguments, and the exact
call's method-forall bindings. A qualified type name must not capture an
unrelated caller formal with the same final component. Nil and Void return
annotations discard values according to Crystal semantics. NoReturn values
do not introduce a returning path.

The function's return ABI and the actual source facts are separate. A broad
restriction may retain its ABI carrier while the completed body establishes
more precise source facts. Dispatch and source restrictions consume source
facts; LLVM calls must still agree with the function's emitted ABI.

A registration hint is not a completed result. When the existing force-lower
depth boundary postpones an exact producer, an ordinary or inline consumer
must suspend before treating provisional Void as a value. Replay retains the
same definition, arena, call shape, and source arguments. A completed generic
family restriction may settle through its validated concrete result facts;
an unresolved method formal cannot use that route.

## Admission and rejection

The candidate covers explicit and implicit returns in ordinary, class, and
yielding methods; actual class-object versus instance results; call-local
forall substitution; and suspension of ordinary declared-return consumers.
Promotion requires the original-first falsifiers below to pass at the exact
source state being committed.

Unknown annotation names, incompatible return values, wrong value kinds, and
unresolved exact return contracts remain errors. A carrier-only lookup cannot
revive a rejected complete source binding. Checks must not be weakened to
accept an application or standard-library call.

The source matcher uses the canonical parent chain, including the built-in
Reference-to-Object and Struct-to-Value edges. Opposite-direction rejection
controls remain required.

A concrete Nil is not a return-inference placeholder. The callsite argument
refiner must retain it rather than replacing it with a declaration lookup's
unresolved method formal. Six original-first Nil/union controls and the
14-case source-kind gate pass after this consumer correction (35q2661).

An abstract callback declaration supplies restrictions, not an executable body.
For zero-ordinary-argument block calls through a closed class family, select
each concrete runtime implementation and retain its exact definition and
arena before inlining. Test deeper descendants before ancestors, including
inherited module implementations. Only normal branch exits contribute values
and capture writeback to the merge. Every runtime arm is checked; an unknown
runtime owner cannot execute an unchecked final implementation. Decline this
closed-family path when a reachable generic template can add runtime owners.
Ten original-first class-dispatch cases pass (35q2732); argument forwarding
and late generic descendant completeness are outside that bounded gate.

The exact selected definition and declaration arena also own each default
argument. Evaluate it in the declaration's namespace with the concrete
receiver and call-local method variables. Preserve the expression's actual
source type and value kind; the parameter restriction remains an upper bound.
A fitting numeric literal can produce an explicit converted value, whereas
an arbitrary numeric expression cannot inherit its formal's type. An enum
symbol default uses its selected restriction as context and must name a
member of that enum.

Keep supplied and defaulted source slots separate through body binding and
replay identity. Materialized defaults may infer a method variable without
filling the supplied-slot omission or borrowing a same-spelled owner variable.
Earlier actuals constrain later defaults. A terminal default stops later
evaluation and the selected invocation, while its own restriction still
follows Crystal's NoReturn admission rules. Rechecking a materialized default
must not select another overload.

Named calls must pair source arguments with the selected declaration's formal
slots, including omitted defaults and external labels. Projected candidate
parameters retain that pairing during method-forall inference. A completed
named binding reaches deferred body lowering even when ordinary instance
arguments need no class-object suffix. Transport requires the exact Def and
arena, complete actual slots, matching TypeRefs, and matching source value
facts; it cannot substitute an ABI-only type for the source contract.

Each generic class or struct declaration also owns its registration namespace.
Capture that namespace with the template's source node and arena, including
nil as an instruction to clear a caller override. Replay each declaration and
reopening in that scope before publishing field types and layout facts. A
namespace inherited from the demand site cannot own a nested field annotation.
Included-module declarations still resolve their fields in the module's own
lexical scope.

Contextual bare-call inference must retain the normal owner-first overload
query. If no owner declaration applies, query the exact global overload with
the same positional/named argument shape. Its result belongs to the selected
definition and retained arena, not a same-name family cache. Infer actual
arguments in the caller's context while keeping the global body's owner empty.
An explicitly returning method named `raise` remains a returning method;
NoReturn follows the selected declaration rather than a spelling heuristic.
The bounded lookup repair does not settle source-level Void results or the
ordinary lowering path's fallback from an incompatible owner overload.

Known open probes include broad or mixed-kind annotated results consumed
before their exact body facts are available, callback method-variable defaults,
unknown external-label admission, and class/instance body reuse through keyword
rest arguments. An
explicit invalid generic call also reaches an internal provenance guard before
its intended source restriction. Passing the bounded return/default corpus
does not close these probes or establish whole-program compatibility.

## Falsifiers and recovery

Run each script with the exact candidate as its argument. The scripts first
qualify their expectations against original Crystal, compare runtime stdout,
and check semantic diagnostics and absence of an executable for rejections.

- `regression_tests/declared_return_contract_repro.sh`
- `regression_tests/source_return_kind_repro.sh`
- `regression_tests/nil_source_result_repro.sh`
- `regression_tests/virtual_source_fact_transport_repro.sh`
- `regression_tests/module_source_value_kind_repro.sh`
- `regression_tests/class_block_source_dispatch_repro.sh`
- `regression_tests/source_default_contract_repro.sh`
- `regression_tests/source_default_block_slot_repro.sh`
- `regression_tests/source_named_forall_contract_repro.sh`
- `regression_tests/generic_declaration_namespace_repro.sh`
- `regression_tests/contextual_global_source_result_repro.sh`

Source, toolchain, input manifests, commands, and outcomes belong in the
corresponding LANDMARK entry. Refresh after result publication, return
validation, exact call binding, arena ownership, replay identity, generic
substitution, or ABI coercion changes. Rollback is the atomic compiler commit;
no application or standard-library migration is part of this contract.
