# Generated allocator source admission with omitted named defaults

An anonymous `*` has `is_splat=true` and no name. It separates named-only formals; it is not a variadic argument. The generated positional allocator proof must permit that separator while rejecting real splats, then validate the original positional limit, required named arguments, ordinary restrictions and generic argument identity. Exact emitted function identity, body revision, source Def/arena and call vector remain mandatory.

The original-first runner checks four byte-exact runtime controls (omitted named default, explicit factory selection, positional defaults, and two generic instantiations). Four negative controls require exit 1, a source type/shape diagnostic, and no executable (wrong scalar, missing required named argument, extra positional argument, and wrong applied generic argument).

Each class has declared storage so this regression isolates an already-emitted allocator. The extra-position control has an explicit factory of the same arity to exercise replacement of a failed source selection by a generated proof. First calls to fieldless classes and extra-position calls without a shape-eligible factory are separate open admission/deferral defects; private packet lavin5039 retains those counterexamples. This regression does not claim those paths, bootstrap closure, or LavinMQ parity.
