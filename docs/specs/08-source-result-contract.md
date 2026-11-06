# Source Result Ownership — Frontier SDD

Status: IN_PROGRESS, 2026-11-06. The bounded return-owner implementation passes
the four original-first gates below against Crystal 1.22.1 (116 fixtures,
35q2635). Result-consumer precision, stock-prelude compilation, fresh bootstrap,
and unchanged LavinMQ execution and upstream test parity remain open.

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

Known open probes include a callback-bound Nil result whose outer overload
still reads an unresolved T, broad or mixed-kind annotated results consumed
before their exact body facts are available, and defaults whose actual type
is overwritten by their formal restriction. These failures were reproduced on
the previous compiler as well. Passing the bounded return corpus does not
close these probes or establish whole-program compatibility.

## Falsifiers and recovery

Run each script with the exact candidate as its argument. The scripts first
qualify their expectations against original Crystal, compare runtime stdout,
and check semantic diagnostics and absence of an executable for rejections.

- `regression_tests/declared_return_contract_repro.sh`
- `regression_tests/source_return_kind_repro.sh`
- `regression_tests/virtual_source_fact_transport_repro.sh`
- `regression_tests/module_source_value_kind_repro.sh`

Source, toolchain, input manifests, commands, and outcomes belong in the
corresponding LANDMARK entry. Refresh after result publication, return
validation, exact call binding, arena ownership, replay identity, generic
substitution, or ABI coercion changes. Rollback is the atomic compiler commit;
no application or standard-library migration is part of this contract.
