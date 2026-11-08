# Source Result Ownership — Frontier SDD

Status: IN_PROGRESS, 2026-11-07. Exact-source S1 35q5962 passes 45
stock Crystal 1.22.1/lazy/eager native property-setter controls (35q5981),
166 focused/adjacent HIR examples (35q5979), and two rooted module-dispatch
HIR guards (35q5984). The nested macro begin and initializer replay refreshes
also pass (35q5965/67). Unchanged LavinMQ passes the former pending initializer
and stops at Char::Reader#next_char result kind (35q5969). Bare self-call result
transport is next. Full prelude, fresh bootstrap and LavinMQ execution/upstream
parity remain open; older certificates retain their recorded source scope.

This is a bounded repair to source result transport in HIR. It does not
replace the semantic architecture transition in specification 07.

## Property-setter source calls

A nonvirtual source setter is an ordinary one-argument call. Select its exact
Def/Arena using actual argument source facts, retain class/instance kind beside
the ABI carrier, and publish that binding before the first return probe can
force the body. Mangling encodes the selection; it does not choose the source.
The exact-source scope must admit that same binding. Depth refusal records the
child dependency and suspends the consumer with the same replay recipe.
A settled source body owns both its return ABI and actual result facts; neither
the RHS type nor a registered return hint supplies those facts. The old
bodiless ivar-parameter fallback remains limited to targets without a source
binding. Terminal source results retain their non-returning control flow.

DoD: deferred_setter_source_result_repro.sh passes the stock oracle, candidate
lazy and ADAMAS_EAGER_MONO modes, including both orders of class/instance inputs
and returned parameters, deep result chains and strict semantic negatives.
property_setter_source_result_spec authenticates selected Def/Arena and result
kind after the CLI registration-before-demand lifecycle; a conflicting prior
exact-source receipt must reject. property_setter_virtual_guard_spec checks
module target/virtual-call preservation with explicitly rooted fixture types.
This direct-call contract does not establish virtual source-kind replay.

The former eager HIR setup materialized bodies without actual argument facts
before any call. Its class-parameter result became an instance fact (35q5968).
That separate source-less materialization limitation is not certified by the
CLI/lazy result gate. The unchanged module-setter suite also fails before
setter dispatch on both baseline and candidate: LinkHolder::Linkable is an
incorrect getter result owner (35q5982/83). Preserve both obligations. The
rooted guard isolates setter dispatch and does not close the owner defect.

## Completed members before callback forall binding

Early binding may inspect an ordinary nilary member only after exact direct
selection and completed source lowering. Its result receipt retains Def/Arena,
body revision/seal, shallow block/instruction/terminator identities and copied
per-leaf source facts. Fresh reachable-return traversal authenticates ordinary
Call leaves recursively; cached caller facts only reconstruct the publication
and cannot establish a fresh callee result. Source annotations are upper bounds.
Unknown, bottom, broad dispatch, module/union receivers and unsettled source
bodies do not obtain a concrete result from an ABI carrier.

A generated allocator has a separate generation-owned Function/revision/layout
witness. Both normal and bare static call emission must retain its exact target.
The fresh consumer rechecks that witness and the emitted Call ABI before using
an ordinary instance result. A source `.new` with the same name cannot borrow
this authority. Tracked body revision and layout invalidation reject it; raw
same-revision generated-body array mutation is a separate open audit obligation.
The source receipt's explicit raw-replacement tests do not certify that bypass.

DoD: callback_member_source_result_repro.sh passes its stock-first positive and
semantic rejection cases in lazy/eager modes; inline_forall_tuple_source_binding
and adjacent ownership suites reject stale source/callee and generated-layout
proofs. Refresh after any relevant selection, body mutation, allocator or replay
change. This bounded contract does not certify full prelude or LavinMQ runtime.

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

A registration hint or known return ABI is not a completed source result.
When the existing force-lower depth boundary postpones an exact producer, an
ordinary or inline consumer must suspend before consuming its source value
kind, including an annotated producer with a known ABI. Replay retains the
same definition, arena, call shape, and source arguments. A completed generic
family restriction may settle through its validated concrete result facts;
an unresolved method formal cannot use that route.

A real nilary member call owns an explicit empty source callshape. Publish it
before result inference can force, depth-refuse or suspend the selected body.
Def/Arena identity alone cannot reconstruct that replay recipe. Empty actuals
do not authorize a required-argument sibling, and a missing callshape is not
evidence of an empty call. Parenthesized and bare nilary syntax retain the same
source contract. `nilary_source_retry_recipe_repro.sh` checks the actual retry
receipt after both annotated child dependencies are refused; it also rejects
stale Def/Arena ownership and keeps explicit-parentheses/strict-arity controls.

## Active physical body ownership during recursive discovery

An in-progress, exact ordinary source body retains its actual Function, Def,
declaration arena, complete formal ABI and declared result after parameter
binding. An ordinary discovery request for those same formals does not become
a second materialization recipe: retain the original actual inputs for replay
and keep the new caller in the family/discovery catalogue. This applies only
to fixed, explicitly typed positional parameters with a declared non-Void
result and known ordinary value kinds. Defaults, rest/named/block slots,
callbacks, inherited aliases and conflicting source facts remain excluded.

Every nonnil argument fact must agree with its stored carrier TypeRef. Missing
fact slots require a complete all-false literal vector; missing facts cannot
establish ordinary value kind by themselves. Source, Function, formal types,
names, defaults, heap/block metadata and result must remain unchanged. Clear
the live receipt on unwind or source replacement. Replay equality remains
strict. A direct recursive Nil-discard result does not add a self dependency;
real child dependencies remain owned by the body.

The five active-body tests cover actual parsed/materialized definitions with
controlled live-capture and mutation probes. Their self-edge test seeds a child
dependency and does not prove actual unwind. Fresh stock-prelude trace 35q5635
separately establishes advancement through the former Exception replay conflict.
The next CallStack error and complete bootstrap/LavinMQ parity stay open.

## Exact primitive source ownership

An intrinsic annotation belongs to the exact source Def and retained arena.
Consume it at that declaration, isolate it across module/nested scopes, and
clear it across intervening non-declaration members. An annotated bodyless
primitive has no ordinary body result to demand or replay. An ordinary sibling,
including an empty sibling, still needs its real source body and restrictions.
The HIR primitive emitter must not transfer a source annotation through a
same-name family fallback. Synthetic builtin registrations retain their
separate path; they cannot authenticate a source annotation.

The HIR-to-MIR Atomic boundary carries an explicit capability only after
authenticating the selected source Def/Arena annotation receipt.
Bind it to the exact emitted target and primitive kind; transport it with the
HIR Call, including its instruction ID, argument IDs, receiver, block, dispatch
kind and result type. Target, argument, call-shape or result-type changes drop
it; same-ID replacement preserves it only when the complete shape agrees.
The constructor is a trusted compiler API, not an unforgeable plugin boundary.
MIR may emit atomic operations
only with this capability and matching operation/operand shape. Names, ABI
shape, module identity and family registry membership cannot grant permission.
An ordinary Atomic::Ops method must execute its source body. Absence of a
capability takes the ordinary call path, never a name-based intrinsic fallback.

Falsifiers: the original-first source_kind_body_demand_repro.sh packet includes
bodyful/empty ordinary primitive-family siblings and a genuine class-valued
rejection. module_primitive_annotation_scope_spec.cr exercises nested annotation
isolation. `atomic_primitive_source_authority_repro.sh` completes the stock
oracle first and checks six ordinary siblings in lazy/eager modes, including
an ordinary overload beside a genuinely annotated one. It also requires an
actual `fence seq_cst` instruction from the annotated fence. The 13 genuine
Atomic controls retain their independent runtime checks. Stop if a sibling
inherits permission or an honest intrinsic loses it; do not restore family
authorization to recover a positive. A result-type repair must revalidate the
exact source/result contract before reissuing permission; generic HIR replacement
cannot do that. Full prelude and bootstrap stay separate.

## Stable arity keys during declaration replay

An occupied declaration slot must not invent a new `$arityN` key for the same
source signature. Preserve the existing deterministic arity, partial restriction,
rest, named-label and block discriminators when registering or replaying that
signature. In particular, replay cannot move a replacement zero-argument method
away from the bare key still used to select its original body.

The original-first source_method_declaration_key_repro.sh gate covers 15 native
controls and two strict rejections per compiler. The focused HIR tests check
occupied-key replay, distinct source shapes, exact Def/Arena publication and
return facts. Existing generic-owner hash controls retain the separate
zero-argument and typed-protocol checks with the stable source key.

Source-ordered publication of conditional or macro-generated module class
methods remains a separate obligation. So do predecessor dispatch, defaulted
overload priority and module-class return validation. ABI mangling must also
retain a selected `**` source shape through later call specialization; equal
NamedTuple carriers do not establish equal source overloads.

## Direct accessor publication during declaration replay

The exact registered Def and declaration arena own an accessor body receipt.
Direct class-body registration retains that ownership even when its optional
source-order recording pass has already been visited. A same-order reparse may
refresh the receipt only for the exact current registered pair. Older declaration
order and a foreign registered arena remain rejected refreshes.

A macro invoked directly in a class body transports that invocation's owner and
source order into registration of generated definitions. Replaying it must
preserve both macro-before-ordinary and ordinary-before-macro winners. This
permission does not extend to included-module expansion. Five focused HIR
examples establish the bounded publication contract; complete stock-prelude and
bootstrap execution remain separate obligations.

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

### Initializer replay binding ownership

A materialized initializer retains its exact source Def and arena, declaration
bindings, selected full-target and base-name registry snapshots, and lowering
context. Preserve absence of a registry entry as well as its values: full-target
lookup may shadow a different base-name map. During replay, body consumers read
these captured entries through a scoped view; nested replay restores the prior
view in ensure. Default inference retains the saved source binding context.

The shared declaration/base registry currently also receives the callsite hint
`__block_return__`. That hint is not a generic declaration substitution. Ignore
only that exact key when checking shared declaration identity; all real generic
bindings and other reserved ABI keys remain strict. A distinct exact target's
hint remains part of its selected context and cannot use the shared-key
exception. Validate live maps outside the replay view before and after lowering,
so the captured view cannot conceal changed source facts.

Retain the independent checks for source/arena/namespace, selected callback
source and ABI, parameter/block carriers, and the retired result lifecycle.
A changed return result is admitted only by the existing exact retired-recipe
replay contract. This repair does not certify other consumers of the shared
callsite hint; moving them to per-invocation ownership remains separate work.

The executable gate is `initializer_binding_owner_repro.sh COMPILER`: HIR
source/replay guards plus stock/lazy/eager native result controls. A fresh
prelude probe must also pass the original Thread replay boundary; a later
independent source-binding failure does not establish full-prelude success.

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

## Macro overload selection owns its declaration metadata

Keep macro candidates in registration order, paired with their definition
arena and full parameter declarations. Same-signature replacement preserves
the original slot. Match the original positional/named/block call shape and
select the first admissible candidate; never reuse a name-level parameter map
or invent a specificity ranking. Preserve named-only, external-label, default,
splat, double-splat and block metadata through the AST cache.

Lookup searches owner/included/parent scopes, then implicit Object, then the
global scope. An ordinary method stops that search; Object fallback cannot
bypass the stop. The original-first macro_ordered_registry_repro.sh gate checks
selection, evaluation order, owner precedence and strict no-executable rejects.
The focused macro_def_parameter_cache_spec.cr checks metadata round-trip and
old-header rejection. This does not close default-expression evaluation,
special-hook accumulation or block-pass normalization before the ** prepass.

## Macro interpolation reflection and block consumption

StringInterpolation#expressions returns ordered AST pieces, preserving text
and each expression's own interpolation payload without evaluating runtime
code. Literal class names describe AST kind even when numeric storage cannot
represent the literal magnitude. This is not a numeric arithmetic guarantee.

The block dispatcher validates the receiver/method pair and argument shape.
It may execute an implemented block API or report a capability error; it must
never fall through to a blockless method and erase the block. Array each/map/
select/reject supply only the element; each_with_index also supplies the index.
Bind only supplied block arguments into the shared macro-variable map. Missing
arguments leave existing bindings unchanged, and assignments and supplied
bindings remain visible after the block. Diagnose an unbound lowercase variable
when it is evaluated, preserving lazy unused branches. NamedTuple select/reject
retain keys and NamedTuple result kind; map returns an Array.

The original-first macro_interpolation_expressions_repro.sh gate covers 44
reflection, runtime and strict-rejection controls. Full macro block-API coverage,
zero-argument top-level builtin fallback and canonical rendering for arbitrary
projected AST nodes need separate evidence.

## Unevaluated macro projections retain their source owner

An unevaluated argument AST and a projected child such as `declaration.value`
retain the exact declaration arena and a source provider bound to that arena.
Check arena identity, node bounds, source ownership and byte bounds before
using a span. Generated parser payloads and original source buffers have
separate ownership records. A macro-body expression with payload-local spans
cannot borrow the expander's primary source merely because its ExprId fits.

Interpolation emits the retained expression source. Explicit `.id` and
`.stringify` operations use structural AST rendering; a typed declaration's
initializer must not disappear when the printer encounters an unsupported
node. Local, instance-variable and class-variable declarations share reflection
of their variable, annotation and optional initializer. An absent initializer
is Nop, while an explicit nil remains a NilLiteral.

Reparse keyword-named arguments in their declaration grammar, with the expected
name, complete input consumption and no parser diagnostics. Ordinary identifiers
keep their existing entry path. Declaration tails share nonempty annotation and
assignment-expression initializer rules. Parenthesized argument parsing must
not impose a declaration ban on a nested call; genuine ternary suppression
still applies. A newline before `=` ends the annotation even inside call
delimiters; a newline after `=` may continue the initializer. Persist parser
changes through AST-cache version 13.

Promotion requires the original-first macro_source_declaration_repro.sh gate,
the focused keyword-declaration and source-provider specs, and neighboring macro
source/error/lookup gates. These checks do not establish every nested type
grammar rule, canonical rendering of arbitrary ASTs, complete prelude,
bootstrap or unchanged LavinMQ execution and test parity.

## Macro array predicates and statement diagnostics

ArrayLiteral#all? and #any? require a block and no positional or named arguments.
Evaluate only the visited elements, through the same shared variable bindings as
other macro Array operations. Stop at the first decisive predicate; an empty
array returns true for all? and false for any?. The result is a BoolLiteral.
Missing block formals remain lazy and preserve an existing outer binding.

Retain every non-output top-level macro directive for compile-time evaluation,
even when its result is unused, rather than only syntactically recognized raise
forms. Empty expansion text is valid; an Error diagnostic from
the macro interpreter must propagate through HIR and reject compilation before
an executable is emitted. Global unknown-method behavior and remaining macro
reflection APIs are separate open contracts. Retaining a directive does not
certify every node the interpreter can encounter.

The original-first macro_array_predicate_repro.sh gate checks seven runtime
controls and three strict rejections; the interpolation/block and CLI expansion
error gates guard shared bindings, lazy branches and rejection propagation.
These checks do not establish complete prelude, bootstrap or LavinMQ parity.

## Macro Begin and conditional values

Execute a handler-free Begin sequence in the same mutable macro context, in
source order, returning the final MacroValue. An empty sequence returns Nop,
matching Crystal's Expressions representation. Preserve that value in call
arguments, assignment RHS, conditions and direct/grouped output expressions;
statement-text rendering cannot substitute for expression evaluation.

A selected empty If/elsif body and a missing else also return Nop. Explicit
nil remains NilLiteral. Test truthiness on the resulting value rather than on
rendered source text. Preserve lazy untaken branches and stop at the first
reached evaluation error. Stock rejects executing rescue/else/ensure
ExceptionHandler nodes in macros; reject those forms when reached rather than
silently discarding their body. Non-output HIR directives propagate the same
interpreter error channel as value expressions.

The stock-first macro_begin_error_propagation_repro.sh gate covers 14 native
controls and seven strict rejections per compiler. These include Nop kind,
condition truthiness, shared sequence effects and error identity. Array/Tuple/
Hash output-root handling is a separate open route; the Begin contract does not
certify every surrounding macro AST kind. No stdlib adaptation or relaxed runtime
type check is part of this interpreter repair.

## Source-owned macro Call projections

Call#args projects positional AST children in source order as an ArrayLiteral,
including the empty array. Call#name is a MacroId; Call#receiver is the exact
receiver AST or Nop; Call#named_args is an ordered ArrayLiteral of NamedArgument
values or Nop when absent. A definite zero-argument MemberAccess is a Call.
Do not reinterpret every Identifier as a Call: a bare identifier can be a local.

Each projected child retains the original ExprId, arena, string pool and
source-provider arena. Equal indices or spans in another arena convey no source
authority. NamedArgument exposes name and value; Splat and DoubleSplat retain
their macro classes and expose the original operand through exp. These fields
accept no arguments. Unsupported call callee shapes reject rather than invent
a receiver or name; a non-call's args is never an admitted empty array.

The macro_call_projection_repro.sh controls qualify construction, projection,
source ownership, interpolation and strict field arity against stock Crystal.
They do not certify every operation on a projected AST child. In particular,
projected NumberLiteral arithmetic remains open: a source-backed MacroNodeValue
does not yet delegate every literal operation to its value implementation.
Call block/block_arg/global?, generalized id, safe navigation and complex
callee projection remain separate open contracts. Preserve strict iterable
validation and existing macro error propagation while extending this surface.

## First-class macro type predicate results

The parser's dedicated IsANode has one result owner: macro value evaluation.
The result is the AST-class predicate's BoolLiteral, shared by output,
assignments, directive conditions, unary/logical operands and ternary
conditions. An opaque unevaluated IsA source node is not that Boolean result.
Evaluate the receiver once in the existing macro context, preserve lazy
unselected branches and propagate the first reached macro evaluation error.

This is macro AST classification, not runtime type inference. A macro argument
keeps its unevaluated source AST; classifying it must not execute its runtime
call. Source rendering must not replace value evaluation or choose the result's
truthiness. The stock-first macro_is_a_value_repro.sh gate covers both selected
branches, value effects, output, logical operands and strict error admission.

## Typeof expression grammar ownership

All typeof payloads, including source-backed annotations, belong to the
ordinary expression parser. Collected annotations and structured types delegate
to parse_typeof; generic arguments use the common type parser, which preserves
the suffix, union and following argument outside the typeof atom. Retain the
validated atom's exact source in the AST arena instead of borrowing a temporary
buffer or maintaining another token whitelist.

The query owns its parenthesis depth and a nonempty assignment-expression list.
A trailing comma and multiline payload are legal; adjacent operands, missing
operands and doubled commas are errors. Recovery must preserve the first
required-argument or required-delimiter diagnostic. It must not skip invalid
payload tokens to manufacture a valid closing parenthesis.

This is a grammar contract. Successful parsing does not certify the semantic
query result or its absence of runtime effects. The source-text typeof resolver
still has recorded failures for Char, queried FFI calls and a multi-expression
is_a? query; those require a separate result-owner repair, not permissive Proc
argument checking or a syntax-specific fallback type.

## Falsifiers and recovery

Run each script with the exact candidate as its argument. The scripts first
qualify their expectations against original Crystal, compare runtime stdout,
and check semantic diagnostics and absence of an executable for rejections.

- `regression_tests/declared_return_contract_repro.sh`
- `regression_tests/source_return_kind_repro.sh`
- `regression_tests/source_method_void_result_repro.sh`
- `regression_tests/source_method_declaration_key_repro.sh`
- `regression_tests/source_array_helper_result_repro.sh`
- `regression_tests/source_kind_body_demand_repro.sh`
- `regression_tests/annotated_source_kind_replay_repro.sh`
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
- `regression_tests/macro_ordered_registry_repro.sh`
- `regression_tests/macro_interpolation_expressions_repro.sh`
- `regression_tests/macro_array_predicate_repro.sh`
- `regression_tests/macro_source_declaration_repro.sh`
- `regression_tests/macro_call_projection_repro.sh`
- `regression_tests/macro_is_a_value_repro.sh`
- `regression_tests/typeof_expression_owner_repro.sh`
- `spec/parser/parser_typeof_expression_owner_spec.cr`
- `spec/semantic/macro_call_args_projection_spec.cr`
- `spec/parser/macro_def_parameter_cache_spec.cr`
- `spec/parser/macro_keyword_type_declaration_spec.cr`
- `spec/semantic/macro_node_source_provider_spec.cr`
- `spec/lsp/string_interpolation_source_cache_spec.cr`

Source, toolchain, input manifests, commands, and outcomes belong in the
corresponding LANDMARK entry. Refresh after result publication, return
validation, exact call binding, arena ownership, replay identity, generic
substitution, or ABI coercion changes. Rollback is the atomic compiler commit;
no application or standard-library migration is part of this contract.


## Macro collection double-splat source contract

HashLiteral#double_splat and NamedTupleLiteral#double_splat return MacroId
source text in entry order, not a runtime ** operand or NilLiteral. Render
values with their macro source representation; preserve and quote named labels.
Accept at most one positional StringLiteral suffix, append it only when entries
are nonempty, and reject other kinds, named arguments and blocks. CharLiteral
is not StringLiteral even if internal value classes share an implementation.

macro_double_splat_contract_repro.sh checks original-first entry and source
kind, four binding/owner shapes, effect order, empty/nonempty separators and
strict diagnostic controls. This boundary begins with evaluated collection and
argument values. It does not certify parser-folded interpolation normalization,
unknown-method fallback, runtime double-splat binding, generated allocator
ownership, full prelude, bootstrap or LavinMQ runtime/test parity. In particular,
missing macro support may not silently erase required constructor keywords.

### Completed initializer block carrier boundary

The selected source initializer owns an untyped block's fallback carrier:
raw callbacks and implicit yield use a code pointer; a captured block uses a
heap Proc. Once the initializer body is complete, each physical block formal
owns both its nominal type and raw/heap representation. An equal Proc TypeRef
does not authorize constructing a heap record for a raw formal.

Forward a raw block only with the same completed TypeRef and authenticated raw
provenance. A heap formal may materialize a raw callback, but boxing preserves
the code pointer and cannot change its normalized input/result signature.
A source Void output is normalized to Nil before this boundary; boxing alone
cannot supply an output adapter. Reject heap-to-raw and incompatible signature
changes. Data formals retain the existing enum source proof and non-narrowing
numeric adaptation.

Gate: allocator_initializer_block_carrier_repro.sh COMPILER runs 30 HIR checks
and three original-first native programs in lazy/eager modes. The heap control
has an explicit zero-input signature to isolate this carrier boundary. The
separate untyped captured-constructor input inference bug remains open.
Refresh after allocator source selection, callback provenance, physical formal
or coercion changes. Rollback is the atomic carrier commit.

### Exact generated initializer call boundary

A generated allocator recipe may retain its one selected inner initialize
Call. The receipt binds Call ID, selected source Def/Arena at both source and
physical keys, completed target Function identity, receiver/argument IDs and
parameter vector. It is usable only while the wrapper's generated body witness
is current. It cannot authorize another call, changed signature or body.

Source restrictions select the initializer. Once its exact body is complete,
its data formal types own the generated wrapper ABI and forwarded call; cached
abstract source carriers must not narrow concrete arguments. Exclude self and
block slots, and reject a mismatched data-slot count. An Int source restriction
may admit Int64 without turning its physical parameter into Int32.

Receiver repair must not rebind default-filled named ABI slots as positional
source arguments. Result repair takes this exact Function's return, including
Void/Nil, independently of broader source caches. Final pre-MIR validation
requires the Call result to equal that physical return. The allocator itself
continues to return the allocated instance. Ordinary calls gain no exception.

Positional source arity rejection stops at the nearest initializer family.
Matching explicit new candidates and included-module fallback retain their
lookup; a NoReturn actual declines the eager proof because evaluation ends
before construction. This does not admit missing keywords for flowing calls.
Named/splat source binding remains outside that positional rejection proof.

Gate: generated_allocator_initializer_binding_repro.sh COMPILER (24 stock-first
native/strict-negative controls), plus generated_allocator_initializer_binding_spec.cr
and generated_allocator_source_proof_repair_spec.cr (nine HIR controls).
Refresh when source selection, ABI slots or either repair pass changes.


### Authenticated initializer replay receipt renewal

A successful initializer replay may retire the captured Function and publish a
new one. Renew a generated allocator's receipt only across that tracked replay:
require the exact retired target, current generated wrapper witness, unchanged
source recipe and Def/Arena, parameter/block ABI, receiver/argument IDs and live
Call shape. Validate every replacement before installing any receipt. An
untracked same-name Function with the same ABI remains invalid.

Renewal does not rebuild wrapper control flow. A change into or out of NoReturn
must fail closed and needs whole-wrapper regeneration before admission. The
internal NoReturn guards test this boundary without claiming source reachability.

Gate: initializer_binding_owner_repro.sh COMPILER includes 29 HIR controls and
six stock/lazy/eager native runs. The natural captured-block replay must renew
its exact Function receipt; call, body-witness and untracked-generation mutations
must remain rejected. Refresh after initializer replay, source publication,
wrapper invalidation, call repair or result-category changes. Rollback is the
atomic receipt-renewal commit.


### Completed Void result materialization

Void is a legitimate completed ABI result as well as a provisional lowering
carrier. An exact source result demand must distinguish them. For a completed
Void body, require its current selected Def/Arena publication, current completed
state and no provisional dependencies. Recompute reachable return producers;
source facts or an SSA Void type alone do not establish completion.

A resolved C declaration or the compiler memory intrinsic signature supplies
an immutable declared return carrier at ExternCall emission. A legacy raw
ExternCall, including the incomplete memory-intrinsic fallback, supplies no
such proof. Exclude NoReturn declarations. Copies and nonempty PHIs retain
proof only when every leaf qualifies. A nonvirtual direct call can consume a
completed source-owned Void body; recursive proof cycles and unknown leaves
fail closed. An explicit resolved :Void discard retains its existing ABI/source
Nil distinction and publication owner. These checks do not admit incompatible
source arguments or replace ordinary return validation.

Gates: authenticated_void_result_repro.sh COMPILER runs nine stock/lazy/eager
native cases and three incompatible-C-argument rejections. HIR controls in
authenticated_void_result_spec.cr cover pending/provisional state, stale
Def/Arena, conflicting/absent declarations, NoReturn, producer mutation,
recursive cycles, virtual calls and the actual incomplete-intrinsic emitter.
Refresh after result publication, CFG/producers, source ownership or extern
signature emission changes. Rollback is the atomic Void result commit.
Full prelude, bootstrap and LavinMQ runtime/upstream parity remain separate.

### Inherited nilary member source continuity

An inherited nilary member selection retains its lexical Def/Arena before
return inference can materialize the concrete receiver's physical symbol.
The physical symbol may initially name an unrelated, cold required-argument
overload. That registry entry cannot replace the selected declaration during
result inference, suspension or replay. Keep its witness separately and permit
re-owning only while that exact untyped shadow is cold. Preserve typed sibling
overloads and validate both optional physical witness fields as one pair.

Carry the same source receipt through replay capture, relay, body generation
and resumed result publication. Resolve source return annotations in their
declaration owner while retaining the concrete receiver's specialization map.
Changed lexical Def/Arena or physical witness invalidates the receipt. Module,
abstract or polymorphic receivers, abstract sources, block/named/required-arg
shapes and primitive-template receipts do not enter this corridor.

Gate: inherited_member_source_contract_spec.cr plus inherited bare-owner,
primitive-template, pending-result, retry-queue, Void and initializer-receipt
guards. inherited_nilary_member_source_repro.sh supplies original-first native
controls and incompatible-argument rejections; those positive native controls
also pass the baseline. The integration discriminator is the unchanged prelude:
baseline rejects a changed String#hash replay source; the qualified candidate
passes it and next stops at AtExitHandlers.run. This does not certify full
prelude, bootstrap or LavinMQ. Refresh after source selection, registry aliases,
declaration ownership or replay changes. Rollback is the atomic compiler commit.


### Publish an observed nilary callshape before canonical target inference

A source nilary member call owns an actual empty `CallsiteArgs` record even
when its selected generic receiver has an unrooted spelling and the emitted
receiver uses rooted type arguments. Publish that observed callshape under the
exact target before the first return inference can suspend. Matching arity or
a similar owner spelling alone cannot create this authority.

Both registry keys must retain the selected Def/Arena, the same canonical
receiver and method, and no typed suffix. Exclude primitive-template and raw
callback receipts; reject a conflicting target callshape. Retain the source
entry and exact-key replay consumers. No family fallback or source restriction
change is admitted.

The actual prelude discriminator is `@@handlers.try(&.pop?)`: the baseline
suspends under rooted `Array(Proc(...))#pop?` without its callshape; the candidate
completes `AtExitHandlers.run`. Five transport/negative controls and 49 adjacent
HIR checks pass. Prelude next stops at an independent recursive argument-shape
conflict in `Exception#inspect_with_backtrace`; full prelude, bootstrap and
LavinMQ remain open. Refresh after owner canonicalization, callsite publication,
source registry, callback receipts or replay changes. Rollback is this atomic
publisher commit.


### Retain a proven positional instance-call rejection

When structured lookup selects no target, a name-only fallback must not erase
an exact source family's rejection of the positional argument count. Reject
only after a coherent Def/Arena census of the concrete receiver and its parent
families proves that every ordinary declaration fails that count. A required
named-only parameter also excludes a positional-only call.

This is a guard for a proven rejection, not a replacement overload resolver.
Unknown/union/NoReturn arguments, self calls, named/block/splat calls, includes,
macros, primitives, generated accessors and incomplete source families decline
the proof. Existing restriction checks and source/replay guards remain intact.

Gate: instance_fixed_arity_repro.sh COMPILER compares an admitted one-argument
call and rejection of an extra argument against Crystal, in lazy and eager
modes. instance_fixed_arity_admission_spec.cr retains default/rest/named-only
and self-redispatch controls; inherited and primitive-source suites protect
adjacent provenance boundaries. Refresh after method indexing, source selection,
callshape or registration changes. Rollback is the atomic arity-guard commit.


### Concrete value self in an inherited redispatching wrapper

An ordinary nilary Object wrapper that calls another overload through self
retains its concrete value receiver as the physical body owner. Its selected
Object Def/Arena remains the lexical source owner. Re-owning the body to Object
would erase the concrete receiver before its internal overload is selected.

Admit only an exact inherited nilary source receipt, the current Object source,
and a concrete value receiver whose wrapper redispatches through self. Keep
primitive-template authorization separate; an inherited ordinary wrapper is
not a numeric primitive. Changed source/owner or nonmatching call shapes retain
the existing guards.

Gate: value_self_wrapper_source_repro.sh COMPILER compares stock/lazy/eager
native output and extra-argument rejection; value_self_wrapper_source_contract_spec.cr
checks physical owner and exact source identity. Refresh after inherited source
selection, numeric owner rewriting, self-call lowering or replay changes.
Rollback is the atomic concrete-value wrapper commit.


### Bare explicit constructors retain their defaulted source call shape

A bare `Type.new` member access with an explicit source declaration retains
named-only default labels after argument materialization. Recover those labels
only from the exact selected Def/Arena and the defaults expanded for that same
zero-argument source call. Bind the physical target with the exact-source
binder and preserve the named call shape in its replay inputs. A declaration
lookup key that encodes default/named slots is not an additional runtime ABI
target to force. Uncertain identity or slot recovery rejects the call.

Gate: defaulted_call_target_source_binding_spec.cr checks source/physical target
identity, default labels and crossed Def/Arena/shape rejection;
bare_constructor_source_shape_repro.sh compares stock/lazy/eager bare,
parenthesized and explicit named output. Its negative control covers an
incompatible ordinary defaulted method argument. An explicit constructor's
incompatible Int64 argument still reaches a late allocator ABI guard on both
baseline and candidate; that separate semantic-fallback defect remains open.
Rest-before-named default expansion is also outside this qualified corridor.
Refresh after default expansion, named slot mapping, target binding or replay
changes. Rollback is the atomic bare-constructor source-shape commit.


### Source witnesses for callback Tuple output variables

An early callback result witness may bind output-only forall variables before
the yielding method constructs a value that depends on them. Preserve both the
type and the class/instance kind of every Tuple slot, including nested Tuples.
Each structured slot must agree with its HIR Tuple descriptor. Matching an ABI
carrier alone does not establish the source kind.

Read callback input restrictions in the exact selected Def/Arena and its input
bindings. Resolve the block's own type paths and formals in its lexical owner,
namespace and captured type bindings. These are separate lookup contexts.
Admit only literal/type-path leaves, ordinary callback parameters, straight-line
block-local assignments and recursive Tuple construction. Retain the existing
completed callback-result validation after lowering.

Unproved captures, calls, control flow, non-local returns, partial input maps,
union inputs and abstract numeric input carriers decline this early witness.
They require a completed source-result proof; a declared return annotation is
not that proof. This boundary does not relax source restrictions or pending
result/replay checks.

Gate: inline_forall_tuple_source_binding_spec.cr and
block_tuple_forall_source_binding_repro.sh COMPILER. Compare original Crystal,
lazy and eager output for ordinary, class-valued, nested and block-local slots;
reject crossed class/instance restrictions. Attack lexical shadowing with a
root type and a same-named type inside the yielding method's owner. Refresh
after source selection, lexical context, callback input/output binding, Tuple
descriptors or result-proof changes. Rollback is the atomic witness commit.


### Resolved type identities remain owned across callback and alias boundaries

A resolved expression path is a canonical type identity. Lower its type literal
without reopening lookup in the current callee namespace. A recorded block
owner remains authoritative even when its class, method and namespace are all
nil: that denotes a top-level lexical scope. It is not missing metadata.

Normalize `.class` and `.metaclass` as structural suffixes by resolving their
base in its declaration scope. Preserve an explicit root through alias storage
and recursive compound restriction parsing. Replacing every expanded alias leaf
with a root is insufficient: an unqualified base must first bind in the alias's
own lexical scope. Class/instance restrictions and actual-result validation
remain mandatory.

Gate: rooted_block_result_namespace_repro.sh COMPILER compares 19 original
Crystal/lazy/eager native programs, including rooted/lexical aliases and alias
chains, nested lexical blocks, mixed union arms and crossed-kind rejection.
rooted_block_lexical_identity_spec.cr exercises complete registration and actual
callback lowering; source_block_result_pattern_spec.cr covers nested, nullable
and metaclass spellings. Refresh after path resolution, alias normalization,
block ownership or callback source-result changes. Rollback is the atomic
resolved-identity commit. This does not certify arbitrary member-call result
proofs, full prelude, bootstrap or LavinMQ runtime/upstream parity.
