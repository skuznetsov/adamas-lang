# Thread-like raw macro branch probe

This no-prelude fixture puts the exact Thread-like condition in a module body.
The module-body macro expansion path reads the raw source text and selects a
branch before parsing its generated class. The two branches publish the same
`Current.current` method name with distinct declared return types and distinct
runtime bytes: `ModernScheduler` prints `A`, while `LegacyScheduler` prints
`B`. It avoids `property!`, whose no-prelude expansion needs
`NilAssertionError` support.

Expected output for each flag set:

| Flags | Expected |
| --- | --- |
| none | `A\n` |
| `without_mt` | `B\n` |
| `preview_mt` | `B\n` |
| `without_mt execution_context` | `A\n` |
| `preview_mt execution_context` | `A\n` |

The `preview_mt execution_context` case matches the reported LavinMQ flag
combination. The discriminator should be run against both the old and corrected
compiler snapshots with the same five flag sets. No build or test was run while
the parent qualification slot is active.

`run_five_cases.sh /path/to/adamas` runs stock, lazy Adamas, and eager Adamas
for every set. Eager mode sets both `ADAMAS_EAGER_HIR=1` and
`ADAMAS_EAGER_MONO=1`. Set `ORIGINAL_CRYSTAL_BIN` and optionally
`ADAMAS_RUN_SAFE` to select the stock compiler and safe runner.
