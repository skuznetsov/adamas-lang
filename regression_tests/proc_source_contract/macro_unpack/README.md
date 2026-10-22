# Macro block-unpack and synthetic-node contract oracle 11841

This packet is a fresh successor to 11830 and adds the three API probes from 11837 plus direct chained and local-variable index controls. It corrects the three fixtures that were not admissible in 11839: rest-pattern cases now inspect normalized macro AST without emitting a rest value or requiring `Array`; the caller-local control uses ordinary source names and tests local preservation, not collision behavior with Crystal's generated `__temp_N` locals.

The retained packet contains thirteen positive runtime cases and three strict negative API cases. Positive outputs are hypotheses until root runs the original-first runner. The three API negatives require the pinned diagnostics `undefined macro method 'Var#name'`, `undefined macro method 'Splat#expr'`, and `undefined macro method 'MultiAssign#value'`. The runner checks compile status and the bounded `run_safe` footer for every stage, compares runtime bytes for positives, and checks the exact expected diagnostic substring for negatives.

## Source basis

Pinned Crystal 1.20.1 `normalizer.cr:432-509` replaces a block's unpacked parameter with a carrier and prepends one or more `MultiAssign` nodes. The flat-rest and nested-splat fixtures inspect those synthetic AST nodes at macro time, but deliberately do not emit the original block body. They therefore test parsing, normalization, and Macro AST projection without requiring the absent `Indexable::Mutable`/array implementation from a no-prelude fixture. Runtime materialization of rest values remains outside this packet.

The temporary-local fixture uses `caller_sentinel_left` and `caller_sentinel_right`. Crystal's normalizer allocates temporary names from a per-prefix counter (`program.cr:669-686`); the earlier 11830 `__temp_1`/`__temp_2` fixture was invalid as a hygiene contract because Crystal itself can allocate and overwrite those reserved-looking names.

Pinned macro API anchors in `macros.cr` are `Var#id` (1265-1270), `MultiAssign#targets` and `#values` (1370-1378), and `UnaryExpression#exp` inherited by `Splat` (1610-1614, 1669-1671). The new flat-rest positive checks these source-supported accessors and generated node text. The negative fixtures attempt candidate-only `Var#name`, `Splat#expr`, and `MultiAssign#value` accessors.

Independent evidence from root's 11843 run on candidate 11836: all six 11807 originals passed; source-forwarded unpack case passed on the candidate, while five expansion cases rejected with `undefined method` for the carrier. This indicates the measured problem reaches beyond the synthetic field spelling and includes how macro interpolation/re-parsing preserves the generated carrier binding. This packet keeps those source-forwarding controls so the next qualification can separate projection from expansion behavior.

Root's 11848 trace narrowed the plain-block failure: expansion emitted ` =67_i32`, because `MacroExpander#evaluate_index_expression` at candidate `macro_expander.cr:2613` resolves only an Identifier as the indexed object, while `evaluate_index_to_macro_value` at 2641 can evaluate an arbitrary receiver. The two new ordinary-block positives discriminate a chained expression (`block.args[0].stringify`) from an index through a saved macro local (`arguments[0]`). They are independent of unpack patterns.

## Limits

- No compiler, build, or native execution was performed while creating this packet.
- Expected results require original-first qualification before candidate results count.
- Rest values are not materialized at runtime here.
- This does not claim general Crystal Macro AST parity or fully hygienic generated temporaries.
- No source, stdlib, or shared-worktree files were changed.
