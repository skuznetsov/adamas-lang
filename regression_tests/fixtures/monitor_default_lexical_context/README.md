# Constructor-default lexical context oracle

The source fixture is a no-prelude compatibility control. It checks four
owner paths while constructors are demanded from `CallerScope`, which defines
conflicting constants:

- a class default produced by a factory method declared later;
- an alias to a class-owned computed default;
- an inherited initializer with a subclass constant of the same name;
- an included initializer with a receiver constant of the same name.

Expected stdout is `ACDE\n`. The regression script compares stock Crystal,
Adamas lazy lowering, and Adamas eager HIR plus monomorphization. The current
HIR split-arena spec is the direct regression oracle for arena-relative default
`ExprId`s; this runtime fixture is a compatibility and owner-path control.
