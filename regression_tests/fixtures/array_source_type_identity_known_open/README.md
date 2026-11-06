# Open applied-module restriction counterexample

Crystal 1.22.1 runs this unchanged source and prints A followed by newline
(35q3306). Baseline S1 35q3269 and candidate S1 35q3300 both reject it
(35q3310/35q3308). The candidate reports the intended canonical actual
Array(Box(LavinMQ::HTTP::Handler)); the baseline reports a locally shadowed
Box as well. Matching the nested applied Indexable restriction remains open.
Do not weaken the restriction or include this source in the passing gate.

Two further stock-qualified cases remain open (35q3319/35q3321): inferred
nonempty arrays lose a rooted constructor result before array composition,
and a class-method forall call rejects before its [] of T body is lowered.
Both reject on baseline and candidate (35q3329/35q3322). Trace 35q3327
refutes repairing the inferred case only at the Array TypeRef consumer.
Their original stdout expectations remain in expectations.json.
