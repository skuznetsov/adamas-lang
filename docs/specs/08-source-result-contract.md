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

Before creating or reusing a materialized method body, publish the exact
registered source definition and arena under its emitted target key. The
logical source key may differ after default inference (`method$arity1` versus
`method$Int32`); a completed body is not authority to reconstruct a missing
binding later. Keep the existing NamedTuple source fallback within this same
publication path and reject a different definition or arena before body reuse.

An automatic stripped-base arena seed requires an existing base definition
identical to the registered definition. A typed or named-only overload cannot
reserve a bare family key with only an arena. Explicit saved module contexts
retain their separate deferred staging path. This registration rule does not
settle virtual dispatch when a child has omitted named-only defaults; preserve
the stock-qualified open companion and its expected child implementation.

A lexical namespace does not prove that a method originated in a module.
Record module instance source ownership on the exact definition and arena,
including effective macro-generated definitions and implicit extend-self.
Exclude nested declaration scopes and explicit class methods. Only that
receipt authorizes replacing or rebasing an included-module alias; a direct
class or Tuple declaration retains its normal precedence even when it has a
namespace override. Keep the different-definition body replacement guard.

A module source receipt identifies its formal names, not an include
application. Remove those names from physical-target caches, receiver aliases,
and ambient caller substitutions. Restore them only from the exact selected
Def, arena and include application; an absent registered map or a module-like
receiver cannot invalidate that exact application. Broad receiver include or
element-type guesses cannot reconstruct missing module bindings. Method-forall
bindings retain their separately validated source call ownership.

A generated allocator has two distinct owners. The selected initializer
owns source parameter restrictions and callback typing. The generated function
owns allocation, its receiverless outer target, argument slots, and physical
ABI. A generic block lookup must not replace that target with the initializer
instance method. An explicit source `self.new` remains an ordinary method and
retains its own actual result.

The generated `.new` expression has the allocated instance as its source type
and instance value kind, including when initialize terminates. Store that
source type on the HIR Call itself and its context entry; local assignment
consumes the instruction's canonical type. Keep the generated Function's
physical bottom ABI separate for exact MIR calls. Setting only cached facts
or context types is insufficient and is rejected by the local-return falsifier.

Retain each generated outer call's exact caller object, ValueId, and generated
target. After deferred generation and RTA, validate its current instruction,
completed generated-body witness, receiverless nonvirtual target, physical
argument count, and callback Proc ABI. A stale or replaced body cannot be
certified from a same-spelled method. Result-only Call/Copy/Local repair may
transport an already-current source or layout proof independently across that
single owned revision; it must not revive an earlier stale proof.

The bounded original-first corpus covers stored callbacks, defaults, recursion,
explicit forwarding, instance/class-object results, and strict return/argument
rejections. Stock-valid `self.new` class/union companions stay explicitly open.
Typed-local coercion, `typeof` result ownership, and source Void callbacks also
remain separate open obligations. This contract does not establish complete
prelude, bootstrap, application linking, runtime, or upstream-test parity.

A bare implicit-self method identifier is a selected call, not a provisional
local value. If its result is pending inside inline/yield lowering, demand the
same exact yield-free target as the parenthesized call path before consuming
its type. Use the force API's inline bypass only in an actual inline context;
its depth, recursion, in-progress-body and yield-free guards remain authoritative.
Defaults, selected Def/arena, result dependencies and runtime virtual dispatch
retain their existing owners. A local of the same name must still win lookup.

The bounded source_array_helper_result_repro.sh corpus covers both demand
orders, direct pointer results, parentheses, annotations and strict return
rejections. Its separately stock-qualified recursive-yield companion remains
open on both baseline and candidate and is excluded explicitly by default;
RUN_KNOWN_OPEN=1 runs that unresolved candidate obligation without changing
its original source or expected output. This local repair does not establish
recursive SCC result inference or full-prelude execution.

A source method whose exact return annotation resolves to Void has a Nil
call result, as in Crystal's check_return_type. Normalize that declaration at
signature/result resolution and body materialization, before publishing source
facts or selecting an outer overload. The body's raw final value is not the
method's source result. An exact-Def cached result may refresh to Nil; retaining
an inferred concrete body type would violate that declared result contract.

A nullable annotation that canonically resolves to Nil has the same method
result discard rule. Require both the canonical Nil carrier and a valid
source restriction reduced to Nil; a Nil.class value, unknown name or
non-Nil union cannot authorize discarding. Preserve the callback's raw yield
value for the callee to consume. The method boundary owns the final discard.
The original-first nil_method_result_contract_repro.sh gate covers three
effect/result cases and four semantic rejection controls (35q3448).

Prove Void through the selected declaration's lexical/type-parameter bindings.
An unknown provisional Void is not evidence of a discard annotation. Nested
Pointer(Void)/Proc(Void) carriers retain their enclosing type. Pass the owning
Def to both annotation resolvers and exclude C fun definitions explicitly;
ordinary extern declarations and a C-ABI main must retain their physical Void
contract. The original-first source_method_void_result_repro.sh gate checks
runtime overload/effect behavior, strict returns and this separate HIR boundary.
The C-entrypoint oracle uses the official primitives prelude because empty.cr
already defines an Int32 main; no standard-library file is modified.

Known open probes include broad or mixed-kind annotated results consumed
before their exact body facts are available, callback method-variable defaults,
unknown external-label admission, and class/instance body reuse through keyword
rest arguments. An
explicit invalid generic call also reaches an internal provenance guard before
its intended source restriction. Passing the bounded return/default corpus
does not close these probes or establish whole-program compatibility.

### Inline callback result ownership

A selected yielding invocation owns a callback result context containing its
exact Def, declaration arena/owner, copied source input bindings and actual
source result facts. Named Proc materialization and direct anonymous yield
substitution publish into this same context. Merge normal and `next` results
before deriving callback-output forall bindings for deferred method returns;
keep `break`, nonlocal return, NoReturn and unresolved Void separate. Actual
Nil is a source result, not evidence of an unknown or terminal result.

Forwarding can pop the block stack while leaving return contexts active.
Bind the function, block identity and active block slot to the exact inline
return context; require that context to remain active, and shadow/restore a
reentrant slot in the inline frame's ensure. Stack-length equality is not an
ownership proof. Publish after caller lexical state is restored to the callee.

The original-first source_inline_callback_result_repro.sh gate covers seven
runtime controls and one strict method-return rejection (35q3236). Mixed
class/instance `next` plus `as(F)` and omitted-default Nil binding still fail
identically on baseline and candidate (35q3225/35q3226, 35q3227/35q3228).
This bounded transport contract does not close either parity obligation.

### Enum primitive predecessor results

An implicit Enum#value predecessor owns the concrete enum base type. Its Int
annotation is a source restriction, not an Int32 ABI choice. Emit a fresh
non-checking cast to the registered carrier even when self already has that
physical type: a primitive integer result must shed nominal enum facts. A real
source previous_def takes precedence, including nonzero-argument predecessors;
resolve its exact body/result instead of substituting the implicit primitive.
Bare helpers with abstract numeric returns demand their completed concrete
result before publishing a source call.

Positional integer-autocast admission retains the exact selected Def. After
body demand, an actual may already have the selected target type despite a
stale pre-inference source hint. Accept that value only when its physical and
nominal source types both equal the target and it is not a type object;
otherwise require the existing source-integer proof before coercion. Do not
reselect a different overload or reuse this rule in unrelated call paths.

The original-first enum_value_source_result_repro.sh gate covers six runtime
controls and a strict enum-identity rejection (35q3267). General previous_def
chains, enum alias dispatch and UInt64 payloads above Int64::MAX remain open.
The frozen unsigned counterexample is retained under
fixtures/enum_value_source_result_known_open with its original C\n oracle;
its measured I/X outputs are failures, not alternate expectations.

### Inherited type lookup precedence

The early nested-type visibility probe and final type lookup must share the
same own-type, included-module/superclass, then enclosing-namespace search.
Otherwise a contextual or suffix alias can replace an inherited source
restriction before the final resolver sees it. Reuse the existing nested-type
resolver and its source-order guards; do not relax a default's restriction or
make an unrelated alias visible as an inherited type.

The original-first inherited_type_source_precedence_repro.sh gate covers six
runtime cases and one strict wrong-enum default rejection (35q3277). Four
positives fail on the baseline (35q3266). This bounded repair does not settle
all alias visibility, annotation qualification or private-type lookup cases.
Two stock-qualified counterexamples, inherited builtin-name aliases and
unrelated suffix-alias visibility, fail identically before and after this
repair (35q3284–35q3286). Preserve their original expectations under
fixtures/inherited_type_source_precedence_known_open.

## Resolved array elements are canonical identities

An explicit Array element annotation is resolved in its source scope once,
including the active method-forall substitutions. Early call inference,
class-ivar inference and literal lowering must consume that resolved name
through the canonical interner. A later Array constructed from an element
TypeRef uses the same canonical boundary. Reinterpreting either result as a
fresh source annotation can bind a global HTTP::Handler to a caller-local
LavinMQ::HTTP::Handler and choose or reject the wrong overload.

The original-first array_source_type_identity_repro.sh gate covers four
runtime controls and one strict relative-type rejection (35q3330). These
include rooted aliases with nilable elements, a rooted applied generic head
with a source-relative child and specialized [] of T. Three namespace/array
neighbors pass (35q3304). The canonical API is not permission to use an
unresolved source fragment after clearing its declaration context.

Keep three stock-qualified counterexamples separate in
fixtures/array_source_type_identity_known_open: applied Indexable matching,
inferred rooted constructor results, and class-method forall admission.
They fail before and after this bounded repair. An extra array TypeRef
consumer change does not repair an already-rebound constructor result
(35q3326/35q3327); investigate its earlier producer rather than widening
Array restrictions or changing variance.

## Method parameters resolve raw annotations in their declaration owner

Pass a parameter's raw source annotation directly to
method_forall_annotation_type_ref with the selected declaration owner and
call-local forall bindings. This applies both to the AST annotation and to
registered parameter metadata. The resolver owns forall substitution and
owner-relative type/alias lookup. An alias-only prepass must not replace an
inherited type with an unrelated suffix alias before that resolver runs.

Preserve own and enclosing aliases, aliases/types inherited through a parent
or included module, and method-forall precedence over owner parameters. A
canonical parameter TypeRef does not permit weakening call admission or
dropping nominal enum facts used by its body.

The original-first method_parameter_source_owner_repro.sh gate covers eight
runtime controls and one strict inherited-parameter rejection (35q3381).
Included-module controls observe actual values, forall shadowing and enum
payload/overload identity. This does not close unresolved method formals or
the separate inherited-parent fallback admission path.

## Declaration isolation restores active caller frames

An ivar initializer's source scope owns its temporary locals. Save each active
inline caller frame's exact Hash reference and contents before entering that
scope. On every exit, restore those contents and reinstall the saved references
in their original slot order. Restoring detached Hashes is insufficient:
control-flow lowering can replace the active stack with cloned maps while the
declaration scope is isolated. Keep caller-frame membership and contents under
the same restoration boundary, as for source named-argument evaluation.

The original-first ivar_default_caller_frame_repro.sh gate covers a dynamic
initializer inside a forwarded inline block, the same initializer inside a
nested Proc, and a literal control (35q3465). Both dynamic cases fail before the
repair and all three match Crystal after it (35q3452/35q3453/35q3462).
Declaration locals must still reject an unrelated caller constant/local;
ivar_default_source_owner_repro.sh is the guard for that isolation boundary.

## Interpolation expressions retain their parser source

A string interpolation piece owns both its expression ExprId and the exact
parser payload that produced that ID. Construct and copy that pair together;
adjacent-literal merging must not detach either part. The AST cache persists
both members and rejects older layouts (version 11).

Macro argument rendering quotes decoded text pieces and embeds the retained
expression source without evaluating it. Reprinting arbitrary child AST nodes
is insufficient: incomplete printers can omit a block or an entire conditional,
changing effects, runtime values and inferred argument types. Child spans are
relative to their interpolation parser payload, so they cannot select text from
an unrelated outer source buffer.

The original-first macro_interpolation_argument_repro.sh gate covers seven
runtime/source controls, including blocks and conditionals, plus a String-to-Int32
rejection. The focused LSP spec checks adjacent merging, cache round-trip and
old-header rejection. This contract preserves expression source; it does not
claim canonical formatting for every possible macro AST operation or close the
separate macro-overload and failed-expansion diagnostic paths.

## Failed HIR macro expansion is not an empty value

At expand_macro_expr, invalid argument reparse is a compilation error. After
expansion, any Error diagnostic stops compilation before callers can convert
an invalid ExprId to Nil or omit generated class members. An invalid result
without an Error remains a legitimate empty expansion. Explicit nil arguments
are ordinary valid AST nodes and must survive cross-arena macro calls.

The original-first macro_expansion_error_repro.sh gate distinguishes empty
output, nested cross-file nil, and valid string-literal output from malformed
generated statements and members. Rejections must name the failing macro and
generated syntax error and must leave no executable. This is a contract for
the HIR expansion seam; other MacroExpander entry points and diagnostic source
locations require separate evidence. A newly exposed transport failure must
be repaired at its producer, not hidden by restoring silent expansion skips.

## CLI macro literals preserve the diagnostic channel

The ordinary CLI macro-literal boundary must inspect Error diagnostics before
accepting generated text or treating empty text as an absent expansion. Valid
partial output cannot erase an earlier failure. Keep warnings nonfatal and keep
valid empty macro loops accepted. The original-first
cli_macro_expansion_error_repro.sh gate checks the error channel independently
of both generated syntax and runtime output. Other expander callers need their
own scoped evidence; do not infer global closure from this boundary.

## Falsifiers and recovery

Run each script with the exact candidate as its argument. The scripts first
qualify their expectations against original Crystal, compare runtime stdout,
and check semantic diagnostics and absence of an executable for rejections.

- `regression_tests/declared_return_contract_repro.sh`
- `regression_tests/source_return_kind_repro.sh`
- `regression_tests/source_method_void_result_repro.sh`
- `regression_tests/source_array_helper_result_repro.sh`
- `regression_tests/source_inline_callback_result_repro.sh`
- `regression_tests/enum_value_source_result_repro.sh`
- `regression_tests/inherited_type_source_precedence_repro.sh`
- `regression_tests/array_source_type_identity_repro.sh`
- `regression_tests/method_parameter_source_owner_repro.sh`
- `regression_tests/nil_source_result_repro.sh`
- `regression_tests/virtual_source_fact_transport_repro.sh`
- `regression_tests/module_source_value_kind_repro.sh`
- `regression_tests/class_block_source_dispatch_repro.sh`
- `regression_tests/source_default_contract_repro.sh`
- `regression_tests/source_default_block_slot_repro.sh`
- `regression_tests/source_named_forall_contract_repro.sh`
- `regression_tests/generic_declaration_namespace_repro.sh`
- `regression_tests/contextual_global_source_result_repro.sh`
- `regression_tests/materialized_method_source_owner_repro.sh`
- `regression_tests/source_module_method_owner_repro.sh`
- `regression_tests/source_heap_block_allocator_owner_repro.sh`
- `regression_tests/ivar_default_caller_frame_repro.sh`
- `regression_tests/ivar_default_source_owner_repro.sh`
- `regression_tests/macro_interpolation_argument_repro.sh`
- `regression_tests/macro_expansion_error_repro.sh`
- `regression_tests/cli_macro_expansion_error_repro.sh`
- `spec/lsp/string_interpolation_source_cache_spec.cr`

Source, toolchain, input manifests, commands, and outcomes belong in the
corresponding LANDMARK entry. Refresh after result publication, return
validation, exact call binding, arena ownership, replay identity, generic
substitution, or ABI coercion changes. Rollback is the atomic compiler commit;
no application or standard-library migration is part of this contract.
