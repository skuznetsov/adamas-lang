# Class block source dispatch

The abstract source declaration owns the call restriction, but is not an
executable body. Before inlining a zero-ordinary-argument block call through a
class receiver, select each concrete runtime implementation, its DefNode and
its registered declaration arena. Dispatch most-specific descendants first.
Included methods retain the selected declaration and concrete receiver.

The original-first runner compares exact stdout and exit status. Negative
cases must fail for an actual Bool-versus-Int32 return mismatch, without an
executable. The positive cases cover concrete control, abstract direct and
included methods, distinct runtime implementations, deeper overrides, an inherited-only module implementation, callback
return values, captured writes, and non-local returns. Three fixtures provide a
minimal raise implementation that exits 99 if reached, because Crystal's
virtual block plumbing references raise even with an empty prelude.

This suite covers closed nongeneric class families and zero ordinary arguments.
It does not claim generic late-descendant closure, argument forwarding,
bootstrap, full-prelude execution, or LavinMQ parity. The separate ensure probe
requires exception-runtime declarations and is not counted as a qualified
empty-prelude oracle.
