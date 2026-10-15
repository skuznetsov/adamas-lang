# HIR Name Resolution Contract

## Control-flow expression statement boundaries (2026-10-15)

A prefix parser consumes its own closing end token and leaves subsequent
statement separators to its enclosing expression/statement parser. Otherwise
an operator beginning the next statement can become an infix operator on the
previous conditional, loop, spawn, select, or begin expression. Preserve the
ordinary infix path when the operator is on the same line, and preserve the
existing newline-dot method continuation rule.

Falsifiers: spec/parser/parser_control_flow_statement_boundary_spec.cr and
regression_tests/control_flow_statement_boundary_repro.sh. Atomic native211
fails 11 of 23 boundary examples; native215 passes those and adjacent parser
controls (69 examples total) and matches original Crystal's ABCDEFGHI runtime
output. Case and semicolon controls detect overbroad changes; same-line
subtraction and next-line chaining guard valid continuations. Refresh after
prefix/infix parsing or separator ownership changes. Declaration/extension
syntax and delimiter-nested expressions remain separate audits in TODO.md.

## Abstract numeric return contracts (2026-10-15)

A direct Int, Float, or Number return annotation constrains membership; it does
not prescribe an Int32, Float64, or abstract object ABI. Infer the concrete
carrier from reachable explicit and implicit returns, validate every member,
and publish it only under the exact selected function symbol. A dead nil tail
after an explicit return contributes no result. Finish a pending numeric body
before a call instruction freezes its result type, including zero-argument
static calls. Free-function parameters preserve the same concrete numeric
callsite carrier as module and class methods.

Falsifiers: spec/hir/abstract_numeric_return_contract_spec.cr and
regression_tests/abstract_numeric_return_contract_repro.sh. Atomic native211
passes 31 focused/neighboring HIR examples and matches original Crystal's
ABCDEFGHI native output. Guards cover wide UInt64 results and arguments,
explicit returns, mixed integer widths, Float32/Float64 and Number results,
invalid String results, and a concrete annotation control. Crystal 1.21 rejects
abstract numeric return unions; the HIR rejection follows that oracle. Refresh
after return inference, cache replacement, or deferred call materialization
changes. Generic return restrictions, negative literals after conditionals,
full MT startup, and LavinMQ broker/spec parity remain separate obligations.

## Selected overload specialization and source binding (2026-10-15)

The selected overload owns the restriction used to decide concrete callsite
specialization. An unsuffixed sibling with another arity or annotation must
not replace that source contract. If an abstract restriction requires an exact
callsite symbol, retain its selected DefNode and producer arena before return
probing or deferred materialization can rediscover a different overload.

Falsifiers: spec/hir/selected_overload_callsite_specialization_spec.cr and
regression_tests/selected_overload_callsite_specialization_repro.sh. Atomic
native201 passes four focused/neighboring HIR examples and the original-first
ABC native guard. Native188 exits 7 on its first wide UInt64 assertion. Controls
cover extend self, a foreign extended producer, and a concrete Int32 overload
beside an abstract sibling of another arity. Refresh after selected-definition
lookup, callsite naming, or deferred materialization changes. Abstract generic
lookup, overlapping normalized overload keys, and LavinMQ parity remain open.

## Source positions and namespace arena ownership (2026-10-15)

Multiline literal scanning must advance source line and column positions once
per consumed byte. A heredoc, percent string, or percent regex inside a nested
class must not invalidate its parser-owned namespace arena. Bind the source
map when testing this boundary: arena checks without source text do not test
the end-line bound used by real file compilation.

Falsifiers: spec/lexer/lexer_multiline_literal_position_spec.cr,
spec/hir/multiline_literal_namespace_registration_spec.cr, and
regression_tests/multiline_literal_namespace_repro.sh. The baseline fails four
lexical position checks and three source-bound HIR cases. Native188 passes
22 focused/neighboring examples and produces the same ABC output as original
Crystal in the native control. The actual Launcher module's end line changes
from 419 to 409 in its unchanged 410-line source file. Refresh after scanner,
span, source-map, or arena validation changes. Cross-file arena fallback
soundness and full LavinMQ runtime parity remain separate obligations.

## Late module reopening exports and lexical context (2026-10-15)

When a module class-method lookup misses its parsed definitions, export only
the requested method from retained extend targets and recorded extend-self
declarations. A source module reopened after its consumer still owns its
generated private overloads. Reuse their DefNode/arena pairs without executing
macro expansion again, preserve explicit consumer definitions, and keep the
receiverless class-call ABI. Deferred module class-method materialization must
apply the registered producer namespace just as class materialization does.
A same-spelled consumer constant must not replace the source's lexical one.

Falsifiers: spec/hir/module_late_extend_spec.cr and
regression_tests/module_late_extend_repro.sh. Native179 aborts on the late
reopening reducer; native181a passes that reducer but fails its lexical
constant control. Native181c passes twelve focused/neighboring HIR examples and
six original-first runtime assertions with identical `ABCDEF` output. Guards
cover disjoint Int32/Int64 private overloads, explicit consumer precedence,
nested modules, late extend self, and a shadowed source constant. Refresh after
module registration order, export lookup, or namespace propagation changes.
Late macro-emitted foreign targets, late class consumers, and overlapping
restrictions remain separate audits in TODO.md; LavinMQ parity remains open.

## Macro-emitted module extend self (2026-10-15)

A selected conditional or named macro can declare `extend self` without leaving
an ExtendNode in the parsed module body. Consume the recorded declaration after
all local module members are registered, then export included methods once via
the ordinary registrar. A recorded self export needs no foreign-arena AST
lookup or generic include argument map. Nested modules use the same operation.

Falsifiers: spec/hir/module_macro_extend_self_spec.cr and
regression_tests/module_macro_extend_self_repro.sh. Native178c fails all three
focused HIR cases and aborts on the original-valid conditional reducer.
Native179 passes fourteen focused/neighboring HIR examples and four
original-first runtime assertions with identical `MNOG` output, covering a
selected else branch, a named macro, a nested module, and an Int64 generic
include control. Refresh after module macro discovery, registration order, or
extend export changes. Macro-emitted includes and multiple generic use sites
remain separate guards in TODO.md; LavinMQ parity remains open.

## Included module methods under extend self (2026-10-15)

`extend self` exports included instance methods through the same class-method
registration path as ordinary module extension. Resolve its SelfNode against
the current module without recording a self-inclusion edge. For a nested
module, perform this export after registering its own definitions, preserving
their precedence. Resolve an unqualified include target in enclosing owner
namespaces before falling back to a global module.

Falsifiers: spec/hir/module_included_extend_self_spec.cr and
regression_tests/module_included_extend_self_repro.sh. Native177 fails the two
top-level HIR cases and aborts on the first ordinary wrapper. Native178 repairs
those but fails the nested case. Native178c passes three focused plus nine
neighboring HIR examples and eight original-first runtime assertions with
matching `PQRSTUVW` output, including a local-method precedence guard.
Refresh after extend-self discovery, nested registration order, or module name
resolution changes. The macro-emitted declaration contract above adds selected
macro and concrete generic include guards; full LavinMQ parity remains open.

## Generated module methods exported by extend (2026-10-15)

Extending a module must register its retained macro-generated instance methods
on the receiving class or module, including private methods called from an
ordinary exported method. Preserve each generated definition's producer arena,
overload restrictions, return annotation, and lexical namespace. A source
module with `extend self` retains the same export obligation even when its
method index uses class-form keys. Register retained definitions without
executing their macro expansion again; preserve the existing source order of
parsed definitions and includes.

Falsifiers: spec/hir/module_generated_method_lookup_spec.cr and
regression_tests/module_generated_method_lookup_repro.sh. Native175j passes two
focused HIR examples, seven neighboring examples, and six original-first
runtime assertions with identical `PQRSTU` output. Included class consumers
also pass a separate runtime probe. The follow-up included-module contract above
repairs the separate `include Source; extend self` forwarding gap.
Refresh after module registration, method indexing, or source-arena changes.
LavinMQ startup and broker/spec parity remain downstream obligations.

## Omitted constructor defaults and inherited field types (2026-10-15)

A zero-argument call selecting an initializer with optional parameters must
evaluate its defaults exactly once and call the selected initializer with their
concrete types. Its allocator symbol must distinguish the empty caller ABI from
the full initializer ABI. Explicit user-defined `.new` retains precedence.

Before inherited-field fixup and final alignment, refresh unresolved deferred
constant types against the complete method registry, then retry unresolved
fields of a zero-argument-compatible initializer. Refresh inference caches
between successful refinements without evaluating any constant at runtime.
Propagate both inherited field types and offsets before body lowering. Do not
introduce a mid-lowering dependent-layout cascade: in-progress bodies can retain
old offsets. Fields depending on required callsite argument types remain a
separate layout-inference obligation.

Falsifiers: spec/hir/zero_argument_constructor_defaults_spec.cr and
regression_tests/zero_argument_constructor_defaults_repro.sh. The runtime guard
checks a forward-defined struct-valued default, first getter reads, inheritance,
explicit arguments, side effects, dependent defaults, and a scalar-returning
explicit `.new`. Native170n passes all 45 focused/neighboring HIR examples and
the original-first runtime guard (exit zero and identical `XXY` output).
The unchanged multithreaded prelude and LavinMQ are downstream checks; reducer
success alone does not certify broker parity. Refresh after constructor
selection, default inference, inheritance, or layout-order changes.

## Module property dispatch and early nested includers (2026-10-15)

An assignment through a module, union, or virtual class receiver must use the
same concrete-target demand and virtual dispatch classification as an ordinary
instance call. A module accessor has no independent object layout. Direct and
chained property assignments therefore require concrete accessor bodies before
MIR dispatch consumes them.

The module declaration prescan retains parsed reopenings before registering
nested classes. An early nested includer must see fields and accessors from a
later reopening. This scan records declarations and cache dependencies; normal
registration continues to own effects. Macro-generated or conditional reopenings
outside that scan remain a separate obligation in TODO.md.

Falsifiers: spec/hir/module_setter_virtual_dispatch_spec.cr and
spec/hir/module_reopening_nested_layout_spec.cr (four focused examples), with
five neighboring HIR suites (17 examples total), and
regression_tests/module_setter_virtual_dispatch_repro.sh (original-first direct
and nested-reopening runtime checks with different layouts and nullable chains).
Native166 fails the setter cases, native167 fails the nested-layout cases, and
native168 passes these guards. Minimal MT prelude startup advances to a separate
Monitor default-argument crash; full LavinMQ parity remains open. Refresh after
module declaration ordering, layout, or concrete-target demand changes.

## Class macro layout declarations (2026-10-15)

A selected class macro branch must register explicit
instance-variable declarations before method-body inference and layout sizing.
Both InstanceVarDeclNode and TypeDeclarationNode use the existing declaration
registration path, retaining the declared nullable type and source arena.
Conditional, begin, and threaded branch consumers share this obligation. An
inactive branch must not contribute fields. Named-macro and macro-for output
that loses declarations during standalone fragment parsing remains open in
TODO.md; dispatch repair does not recover an already lost declaration.

Falsifiers: spec/hir/macro_class_ivar_declaration_spec.cr and
regression_tests/nullable_struct_field_take_repro.sh (original-first nullable
value-struct read, clear, and repeated take). The unchanged LavinMQ startup is
the downstream check. Refresh after class macro dispatch or layout registration
changes; passing the reducer alone does not certify scheduler or broker parity.


## Macro call and statement boundary (2026-10-15)

Macro trivia skipping does not authorize a parenthesized call to consume a
brace or do block starting on a later line. The call's final source span,
including its closing parenthesis, determines trailing-block eligibility.
A named tuple following an annotation call must remain a separate map-body
statement, preserving its transform value when generating overload arguments.
Same-line brace and do blocks remain attached to the call.

Falsifiers: spec/parser/parser_macro_block_statement_boundary_spec.cr (five
examples) with the neighboring macro argument and named argument/block specs
(17 total), and regression_tests/macro_block_statement_boundary_repro.sh
(original-first explicit annotation and fallback-type runtime checks).
Native164 fails both newline parser cases and the runtime reducer; native165
passes these guards. Refresh after call-span, trivia, or block-attachment
changes. Other explicit newline-consuming call consumers and nilable
metaclass overload resolution remain separate open obligations in TODO.md.


## Explicit Proc input arity (2026-10-15)

An explicitly empty Proc input list is present type information. It must not
fall through to yield/body inference as though no annotation existed. Expected
callback arguments remain in the emitted ABI even when the source block binds
fewer names. Resolved block parameter types replace corresponding expected
entries by index and append only previously absent positions.

Falsifiers: spec/hir/block_proc_expected_arity_spec.cr (two examples),
regression_tests/block_proc_expected_arity_repro.sh and
regression_tests/captured_proc_zero_input_repro.sh (original-first isolated
runtimes), green on sealed native164. The full LavinMQ spec build still rejects
a separate generic Fiber return-R initializer. Refresh after callback type or
capture ABI changes; no full LavinMQ parity claim follows from these guards.


## Program mixin lexical context (2026-10-15)

A top-level include or extend may materialize an instance method as a bare
Program function. Its emitted symbol does not replace its declaring module's
lexical namespace. Body lowering consumes the registered namespace override,
including type lookup and protected access. Protected checks use that lexical
owner before the receiver owner; unrelated modules remain rejected, and an
explicit receiver does not acquire permission to call a private method.

Falsifiers: spec/hir/program_mixin_lexical_context_spec.cr (five examples)
with spec/hir/top_level_program_mixin_spec.cr (three neighboring examples),
and regression_tests/program_mixin_lexical_context_repro.sh (three allowed
runtime cases and two rejected cases, original-first). Native162 fails the
three positive HIR cases; native163 passes all eight and the runtime guard.
The unchanged LavinMQ spec build passes Spec::Methods#around_each and reaches
the separate Fiber Proc ABI conflict. Refresh after lexical namespace or
visibility changes; this evidence does not certify LavinMQ parity.


## Module default argument result inference (2026-10-15)

An omitted positional argument binds its default in the selected callee's
source arena and lexical environment. Earlier actual/default bindings are
visible to later defaults. An explicit argument whose type is unknown stays
unknown; an explicit named argument is not overwritten by an omitted-position
default. Both CallNode and bare zero-argument MemberAccessNode consumers may
use those bindings to infer an unannotated module method's return type.

Falsifiers: spec/hir/module_default_argument_return_spec.cr (eleven examples)
and regression_tests/module_default_argument_return_repro.sh (three
original-first runtime cases), green on sealed native156. This evidence covers
default result inference only; it does not certify captured callback ABI,
Signal startup specialization, or LavinMQ parity. Refresh after default or
selected-definition context changes.


## Select action expansion (2026-10-15)

The legacy HIR path admits select conditions represented by calls, including
member access, global calls, and assignment from a call. It constructs each
receiver and argument once, preserving named arguments and blocks, then calls
::Channel.select or ::Channel.non_blocking_select with the action tuple.
The returned zero-based index selects the original branch body; assignments
cast the returned value using semantic typeof of the original operation.
Type queries must not execute that operation. An existing empty else is a
nonblocking fallback; an absent else raises on an invalid selected index.
Generated locals are inaccessible to source identifiers.

Falsifiers: spec/hir/select_expansion_spec.cr (nine examples) and
regression_tests/select_action_dispatch_repro.sh (ten identical original-first
output lines). Native162 uses a deterministic Channel adapter to isolate the
language expansion; it does not certify stdlib scheduler behavior. Semantic
infer_select still returns its earlier Nil placeholder. Native163 repairs the
subsequent protected-call lexical-owner defect. Refresh these guards
when action construction, branch result joining, or type-query lowering changes.


> Status: Draft v0.1, 2026-05-08.
> Scope: HIR ownership, nested names, type literals, and source-backed recovery.

## 1. Purpose

HIR is the first durable compiler boundary in Crystal V2. Most bootstrap
frontiers in the current project are not "bad LLVM" first; they originate as
wrong ownership, wrong receiver shape, or wrong source recovery in HIR.

This contract defines the HIR invariants that downstream MIR and LLVM are
allowed to trust.

## 2. Qualified Ownership

### 2.1 Canonical Names

Every class, module, lib, enum, alias, and function owner MUST have one
canonical qualified name.

Nested declarations MUST be joined with owner-aware logic:

```text
qualified_nested_type_name(owner, child)
```

The join MUST:

- preserve an already-qualified `child` when it is already under `owner`;
- prefix only genuinely relative children;
- avoid duplicating namespace components.

Falsifier: `Float::FastFloat::ParsedNumberStringT` MUST NOT become
`Float::Float::ParsedNumberStringT` or
`Float::FastFloat::Float::FastFloat::ParsedNumberStringT`.

### 2.2 Self-Reopen Wrappers

A qualified reopen wrapper whose canonical name is the current owner itself
MUST NOT be registered as a recursive nested module.

Its direct nested types and aliases still MUST be visible under the owner.

This prevents `Float::FastFloat -> Float::FastFloat` self-recursion while
preserving `Float::FastFloat::ParsedNumberStringT`.

## 3. Builtin and Top-Level Names

Unqualified builtin/top-level type annotations inside a nested owner MUST remain
top-level unless the active namespace chain structurally records a nested type
with that name.

Registry fallback alone is not sufficient evidence that `String` inside
`Float::FastFloat` means `Float::FastFloat::String`.

## 4. Type Literals

Type literals are compile-time values in HIR. Calls to name-query methods on a
type literal MUST lower to compile-time string values unless a real dot-method
override exists on the owner/parent chain.

Covered name-query methods:

- `to_s`
- `inspect`
- `name`

Invalid lowering:

```text
Bool.to_s -> Bool$Dto_s runtime/static stub
NameProbe.name -> NameProbe$Dname runtime/static stub
```

Valid lowering:

```text
NameProbe.to_s -> "NameProbe"
NameProbe.name -> "NameProbe"
```

Guard: `regression_tests/p2_type_literal_name_query_no_stub.sh`.

### 4.1 Type-Visible Runtime Values

`typeof(expr)`, runtime `expr.class`, explicit type literals, and type-literal
name queries are one semantic family. They MUST NOT be implemented as unrelated
runtime pointer placeholders, interpolation-only side paths, or backend string
stubs.

HIR SHOULD own a single type-visible value fact that records:

- the semantic `TypeRef`;
- the canonical display name;
- the origin of the value (`typeof`, runtime `.class`, explicit type literal,
  or name query);
- whether the value is compile-time-only or needs runtime stringification.

Direct output and interpolation MUST consume the same fact. A guard that only
proves one of `puts typeof(x)`, `"#{typeof(x)}"`, `puts x.class`, or
`"#{x.class}"` is not wide enough to claim this contract fixed.

Current frontier: the B3 original-vs-stage oracle prints blank `TYPE=` and
`UNION=` lines in the stage output where original Crystal prints `Int32`. This
is a `TypeValue` / `RuntimeTypeIdentity` frontier, not permission for a
string-only `typeof` patch.

Focused guard: `regression_tests/type_value_runtime_identity_contract.sh`.
It is strict by default and measured-red only with
`ADAMAS_EXPECT_TYPEVALUE_MISMATCH=1`.

Current H6-core guard:
`regression_tests/type_value_core_runtime_identity_contract.sh`. It covers the
bounded owner-fact surface for direct/interpolated `typeof(1)`, multi-arg
`typeof(1, "x")`, direct/interpolated `1.class`, local and parenthesized
nilable `.class`, and type-literal name/string queries.

Known residual: dynamic multi-variant union `.class` still requires a runtime
type-name service rather than compile-time union display. Guard:
`regression_tests/type_value_dynamic_union_class_residual.sh`, measured-red
with `ADAMAS_EXPECT_DYNAMIC_UNION_CLASS_MISMATCH=1`.

Important boundary: a `RuntimeTypeIdentity` fact is not automatically a string.
Explicit type literals may carry identity for name/query semantics but must not
be stringified when used as normal call arguments. The concrete guard is
`regression_tests/test_byteformat_decode_u32.cr`: `IO::ByteFormat::LittleEndian`
must remain a format/type value so `String#encode(UInt32, IO)` materializes
normally.

## 5. Source-Backed Recovery

When generated stages cannot trust raw frontend slices, HIR MAY recover
parameter, return, receiver, and owner metadata from source providers.

Recovery MUST obey these limits:

- It MUST use the file/provider boundary, not raw arena slices that the
  generated compiler has already shown to corrupt.
- It MUST preserve explicit static owner names for class methods.
- It MUST NOT broaden into source-first body scans for generic templates unless
  a focused falsifier proves the scan is required.

Refuted branch: broad source-gated generic-template body scan regressed earlier
around `Crystal::PointerLinkedList` / trace paths and is not an acceptable
general fix.

## 6. Function Body Presence

HIR MUST distinguish a registered function stub from a function with an emitted
body.

A function has a body when at least one block has emitted instructions or a
real terminator. An initial `Unreachable` terminator on an empty entry block is
not evidence of a body.

Downstream stages MAY use this to avoid trusting stale stubs.

## Class-variable Hash annotation identity (2026-10-15)

For an explicitly typed class-variable initializer such as `{} of K => V`,
resolve both annotation names in the declaring owner and retain their TypeRefs
when constructing `Hash(K, V)`. Converting names to short strings first can bind
`::Signal` to an unrelated nested `Crystal::System::Signal` module and produce
a different Hash specialization. This contract covers explicit Hash annotations;
other class-variable initializer forms remain separate.

Falsifiers: `spec/hir/classvar_absolute_hash_type_ref_spec.cr` and
`regression_tests/classvar_hash_annotation_owner_repro.sh` compare the stdlib
`Signal::Handler` alias with direct Proc and explicit alias annotations.
Native168 reproduces a missing Hash specialization; native169 matches original
Crystal's three successful writes. The concurrency-flagged LavinMQ startup remains blocked
by a separate null Monitor initializer; this guard does not certify app startup.
Refresh after class-variable inference or annotation owner resolution changes.

## Retained block carrier agreement (2026-10-15)

The selected source Def and its arena determine whether a named block escapes
as a Proc value before HIR signature materialization. Once a real HIR body and
block parameter exist, their carrier metadata is authoritative. A provisional
function's default metadata is not a carrier decision. Method names and sibling
overloads do not establish the callback representation.

A forwarded, returned, or captured block must retain its code/environment pair.
Forward the existing value after choosing the emitted target, including plain
allocator names whose trailing parameter is an ordinary Proc. Raw callback
coercion must consult the caller's actual block carrier; an existing Proc must
not be wrapped as a code pointer.

Falsifiers: `spec/hir/block_carrier_selection_spec.cr`,
`spec/hir/forwarded_block_carrier_spec.cr`, and
`regression_tests/forwarded_block_capture_repro.sh`. Atomic native215 prints
202/202/405/405; native234 and original Crystal print 101/202/304/405. Seven
focused examples and `regression_tests/raw_proc_pair_constructor_contract_repro.sh`
pass on native234. This covers the retained-block cases and existing raw Proc
constructor contract. Mixed yield/retention and stdlib Once raw/heap variants
remain separate obligations; full LavinMQ parity is open. Refresh after block
selection, forwarding, HIR signature materialization, or Proc coercion changes.
