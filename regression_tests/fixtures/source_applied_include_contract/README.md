# Source-applied module and body ownership

These no-prelude fixtures check concrete Tuple and generic include bindings,
no-argument result inference, callback inputs, lexical owner selection, direct
receiver overrides, included-hook source order, exact getter/Def body ownership,
and the source provider used by `super`. Every `.cr` file has an adjacent
`.expected.stdout` byte oracle. The runner checks lazy and eager HIR; set
`CRYSTAL_BIN` to qualify the same programs with the original compiler.

The getter/rest fixtures preserve distinct zero-argument and rest call shapes.
The provider fixture uses two opposite include orders to detect lost source
provenance even when the selected methods have the same argument ABI.
