# Known Bugs in Combined Regression Tests

## test_strings_join — FIXED
- **Fixed**: Inline yield arity check was too weak (`non_block_params == 0` instead of `< call_args.size`), causing `Enumerable#join$block` (1-param wrapper) to be inlined instead of `Enumerable#join$arity2_block` (2-param iteration body). Three fixes: tightened arity check, added arity guard on `yield_function_name_for` fallback, added module-level arity variant search.

## test_oop_dispatch — FIXED
- **Fixed**: `self.class` type literals (nil pointers at runtime) were passed to `.to_s` in string interpolation, calling `Person#to_s(null)`. Added dot_class_literal check in `lower_string_interpolation` to convert type literals to class name strings.

## test_generics_unions (CRASH)
- **Pattern 1**: `Box#map` with `forall U` — generic type parameter not correctly resolved
- **Root cause**: V2's forall handling doesn't properly create new generic instantiation for return type. `Box(String)` gets value from `Box(Int32)` instead.
- **Pattern 2**: `Pair#swap` returning `Pair(B, A)` — multi-type-param generic swap
- **Root cause**: Similar — V2 doesn't properly instantiate the swapped generic type.
- **Crash**: Segfault in String#bytesize (null String from wrong generic instantiation)
- **Tracking**: RC-forall-generics
