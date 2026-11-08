# Bare self-call source-result regression

Bare methods whose bodies are deferred must publish the same explicit empty
call shape, exact source selection, parameter/default binding, result dependency,
and settled source facts as ordinary parenthesized calls. This packet compares
stock Crystal first, then the candidate in lazy and ADAMAS_EAGER_MONO modes.

The controls cover deep annotated and unannotated result chains, implicit field
reads/writes, explicit parentheses, virtual families, defaults, class-valued
results, class/instance methods in nested namespaces, local shadowing, enum
predicates and Proc/Char intrinsic precedence. Missing required arguments and
class-to-instance misuse must remain semantic rejections.

The empty-prelude Enum/Char declarations reproduce the minimal installed
Crystal definitions needed by the original oracle; no standard-library files
are modified. Every compiler and executable runs through scripts/run_safe.sh.
The runner verifies exact output and exit/resource footers, then removes native
executables and caches. These controls do not establish full prelude, bootstrap
or LavinMQ runtime parity.


Known-open arity admission is outside this result-transport certificate.
The `known_open/` sources are rejected by stock Crystal but were already accepted
by the pre-change compiler. A blanket new self-call arity refusal was falsified
by the three inherited-arity positives: ChildShape may supply the zero-argument
method missing on BaseShape. Deferring eager bodies alone was also insufficient.
The eventual arity repair must retain the concrete receiver while materializing
the inherited body and reject actual BaseShape calls. These fixtures remain
visible and are not counted as passing gates. No arity or type guard is weakened
by the result-transport change.
