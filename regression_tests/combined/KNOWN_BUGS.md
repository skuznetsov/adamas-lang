# Known Bugs in Combined Regression Tests

## test_strings_join (CRASH)
- **Pattern**: `Array(Bool)#join("|")` — join on non-String arrays
- **Root cause**: V2 assigns wrong method body to join overloads. All join variants get the wrapper body instead of the correct iteration body. `Indexable#join` calls `super(separator)` but the super resolution picks wrong DefNode.
- **Crash**: Segfault in String#bytesize (null pointer from corrupted return value)
- **Tracking**: RC-method-body-assignment

## test_oop_dispatch (CRASH)
- **Pattern**: Module method calling `self.class` in string interpolation
- **Root cause**: `self.class` in module method context returns empty string / null receiver. When module includes trigger `to_s` call, `self` is null.
- **Crash**: Segfault in Person#to_s (null self, accessing field at offset 0x8)
- **Workaround**: Avoid `self.class` in module methods; use direct instance var access instead
- **Tracking**: RC-module-self

## test_generics_unions (CRASH)
- **Pattern 1**: `Box#map` with `forall U` — generic type parameter not correctly resolved
- **Root cause**: V2's forall handling doesn't properly create new generic instantiation for return type. `Box(String)` gets value from `Box(Int32)` instead.
- **Pattern 2**: `Pair#swap` returning `Pair(B, A)` — multi-type-param generic swap
- **Root cause**: Similar — V2 doesn't properly instantiate the swapped generic type.
- **Crash**: Segfault in String#bytesize (null String from wrong generic instantiation)
- **Tracking**: RC-forall-generics
