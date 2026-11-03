# Lexical constant lookup contract fixtures

The eight primary fixtures are copied from the used-path oracle set
`inputs35q593_lexical_constant_used`; the path cases invoke their method so the
constant read is demanded. Two controls are copied from
`inputs35q579_lexical_constant_lookup`: they invoke the same invalid reads but
discard the result, and stock Crystal still rejects them.

The added absolute enum and generic `T::VALUE` fixtures are positive controls.
The qualified and absolute missing-owner fixtures must fail with the recorded
undefined-constant diagnostic. The two nested-initializer fixtures are
additional allocator materialization controls: stock prints `A`; the frozen
q595 candidate currently rejects `CODE` in lazy/eager mode, so they remain
falsifiers for the next production candidate. Positive outputs are byte-exact,
including the trailing newline. The companion script compiles all stock cases
first, then compiles and runs Adamas in lazy and eager modes through
`scripts/run_safe.sh`.

Cases 20–23 preserve the generic class-body constant scope oracle: the generic
class's own `CODE` prints `B` from class and instance methods, while a method
that refers to `MISSING_CODE` rejects even when the calling module defines that
name.

## Cases

| Fixture | Expected result |
| --- | --- |
| `01_*` | Reject an included method constant available only on its includer. |
| `02_*` | Read the included module's value (`A`), not the includer's. |
| `03_*` | Reject a qualified nested path available only on the includer. |
| `04_*` | Read the included module's nested value (`A`). |
| `05_*` | An inherited body reads the parent's value (`A`). |
| `06_*` | A lexical module constant (`B`) shadows the root constant. |
| `07_*` | `::ROOT_VALUE` reads the root constant (`A`). |
| `08_*` | A legal root fallback from an included method reads `A`. |
| `09_*`, `10_*` | Discarding the invalid call result does not suppress rejection. |
| `11_*` | An absolute enum member path lowers and runs (`A`). |
| `12_*` | A generic `T::VALUE` path lowers and runs (`A`). |
| `13_*`, `14_*` | Missing qualified and absolute owners reject exactly. |
| `15_*`, `16_*` | A nested allocator keeps its declaration namespace (`A`). |
| `20_*`, `21_*` | Generic class and instance method bodies read their own constant (`B`). |
| `22_*`, `23_*` | Generic class and instance method bodies reject a caller-only constant. |
