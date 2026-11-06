# Bare implicit-self helper result demand

The main original-first gate has 14 cases: 11 pointer/helper result controls
and three guards for local shadowing, defaults and virtual child dispatch.
The original core was stock-qualified by 35q3132; all four additional controls
were stock-qualified by 35q3145. Every gate execution reruns the stock oracle.
Two core negatives require semantic method-return diagnostics, exit 1 and no
executable. They must not be turned into unknown/Void acceptance.

The separately hashed yielding_reentrant_helper.cr remains a known-open
stock-valid case. Both baseline S1 35q3098 (35q3153) and the earlier combined
candidate (35q3151) reject it. Its recursive yield result requires a separate
inference/fixed-point investigation. The runner always stock-qualifies it,
reports its exclusion, and checks it against the candidate only with
RUN_KNOWN_OPEN=1. Its source and A\n expectation are preserved unchanged.

Actual stock-stdlib Array#shift is a separate full-prelude companion. The
bare-helper repair passed its previous result error but reached the existing
Errno#value frontier (35q3143); this establishes no runtime or bootstrap result.
