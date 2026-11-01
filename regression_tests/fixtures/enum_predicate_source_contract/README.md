# Source enum predicates

The fixtures compare bare calls, explicit empty calls, and explicit receivers
against stock Crystal with an empty prelude. Positive cases cover bit membership
for rooted `@[::Flags]`, equality for ordinary enums, implicit `None`/`All`,
explicit `None = 0`, and a source-defined predicate overriding the generated one.
Each positive fixture has its own byte-exact expected output.

Negative cases require an undefined-method or undefined-constant diagnostic.
An inferred result type is not a method declaration; neither `all?` on Flags nor
`all?` or `size` on an unrelated class becomes callable from an inferred signature.
Only Flags supplies implicit `None`/`All`. An undeclared enum constant must not
fall through to the generic unresolved-path zero literal. Constant names stay
case-sensitive even though symbol auto-casting accepts normalized member names.

Run `regression_tests/enum_predicate_source_contract_repro.sh <compiler>`.
The script qualifies both lazy and eager HIR, using the safe runner for compilation
and native execution.
