# Materialized method source ownership

The `self_bare_then_member.cr` case is the behavioral regression: a bare
identifier call first forces a defaulted method body to resolve its result;
a later explicit-self call reuses that body. Crystal 1.22.1 prints `AA`.
Before the repair, Adamas rejects it because the physical `$Int32` body has
no Def/arena registration even though its `$arity1` source owns both.

The other fixtures guard explicit/default call order, receiver parameters,
inherited/included/generic owners, class methods, named-only defaults and
strict argument/return rejection. Two further controls cover macro-if and
macro-generated declarations; they do not prove every transported-source
reparse path. They do not establish full prelude,
bootstrap, LavinMQ execution, or upstream test parity.

Run the script with an explicit compiler and ADAMAS_ROOT_DIR when the binary
is outside a repository. Every compile and program execution uses run_safe.sh;
stock expectations are qualified before candidate checks. Negative cases
must report the semantic diagnostic and leave no executable.

The cross-file inherited named-default companion remains OPEN: stock prints
`A`, while baseline and candidate print `B`. It is stock-qualified and excluded
from candidate success. The intermediate candidate's orphan-arena rejection
is a separate registration failure, not evidence that dispatch is correct.
