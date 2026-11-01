# Packed positional splat source identity

`main.cr` is a no-prelude runtime oracle. It explicitly requires `comparable` before `tuple`. Expected stdout is `ABCDEFGEFEF\n`:

- `A`: getter selected for zero arguments despite the same name having a rest overload.
- `BC`: typed `*args : Int32`, one and two elements return distinct bytes.
- `DE`: untyped `*args`, one and two `Int64` elements return distinct bytes.
- `FG`: typed `*args : Int64`, one and two elements return distinct bytes.
- `EF` / `EF`: fixed and rest overloads remain selected across both source orders.

`wrong_element.cr` must fail compilation because `Bool` does not satisfy the
`Int32` rest restriction. The runner checks both lazy and eager HIR modes. It
uses `scripts/run_safe.sh` for compiler and fixture processes.

This candidate admits only a single positional rest formal. A rest formal with
fixed positional prefix or suffix, named-only parameters, a block parameter,
`**args`, or method-level `forall` needs a separate packed argument-layout
proof and is intentionally outside this narrow handoff.
