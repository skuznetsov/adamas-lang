# HIR Name Resolution Contract

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
