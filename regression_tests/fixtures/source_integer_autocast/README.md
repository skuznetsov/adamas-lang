# Source integer autocasts

Original-first empty-prelude regression: twenty-one positive programs and
twenty-four source-type rejections. Positives compare stdout byte-for-byte and
require exit 0 with no runtime stderr; negatives require compiler exit 1,
a type/overload diagnostic naming the call, and no emitted executable.

The ordinary source overload pass retains priority. Only a complete plain
positional call with no ordinary match may retry using representable integer
literals or a runtime integer whose entire domain fits the target. Bounds,
signedness, ambiguity, exact overloads, class/instance/default/factory calls,
and left-to-right argument evaluation are exercised. A type object, enum
carrier or Char value cannot become an integer argument through this pass.
Primitive type objects exist before the prelude and preserve local/forall
provenance; all fourteen intrinsic primitive type values are checked.

The reference is the original Crystal compiler, not an expected-output stub.
The helper deliberately excludes named, splat and block source binding, float
conversions, and literal Int128/UInt128 conversion. Known primitive membership
in abstract numeric restrictions is checked before ABI erasure: Char and
opposite signedness cannot satisfy Int::Signed/Unsigned, Char cannot satisfy
Number/Number::Primitive, and a namespaced Int is not the intrinsic abstract
Int. Excluded call shapes, full metatype restriction matching, bootstrap,
and unchanged LavinMQ runtime/spec parity are separate obligations.

Qualified .class restrictions and runtime values passed as metatypes have
separate known failures on the parent compiler. This regression establishes
only the numeric conversion and primitive-membership scope described above.
