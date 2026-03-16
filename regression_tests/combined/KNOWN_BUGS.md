# Known Bugs in Combined Regression Tests

## test_strings_join — FIXED
- **Fixed**: Inline yield arity check was too weak (`non_block_params == 0` instead of `< call_args.size`), causing `Enumerable#join$block` (1-param wrapper) to be inlined instead of `Enumerable#join$arity2_block` (2-param iteration body). Three fixes: tightened arity check, added arity guard on `yield_function_name_for` fallback, added module-level arity variant search.

## test_oop_dispatch — FIXED
- **Fixed**: `self.class` type literals (nil pointers at runtime) were passed to `.to_s` in string interpolation, calling `Person#to_s(null)`. Added dot_class_literal check in `lower_string_interpolation` to convert type literals to class name strings.

## test_generics_unions — FIXED
- **Fixed**: Multi-type-param generics (e.g. `Pair(A, B)`) were not being monomorphized because `infer_generic_type_arg` only handled single-param templates. Added `infer_generic_type_args_multi` which infers each type arg from the corresponding constructor arg. Applied at all 4 `.new` call sites.
