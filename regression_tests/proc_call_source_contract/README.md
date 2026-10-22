# Concrete Proc call source contract

This original-first no-prelude oracle checks concrete `Proc#call` argument
admission before ABI coercion. Six positive cases use the exact numeric input
type. Thirteen negative cases cover numeric literals and expressions that
ordinary method calls may autocast, incompatible scalar input, and missing or
extra arguments. Crystal treats the `proc_call` primitive as a strict call;
ordinary numeric autocast rules do not apply here.

Every compiler and emitted program runs through `scripts/run_safe.sh`. The
oracle checks exact stdout for accepted programs, a semantic diagnostic and no
executable for rejected programs, and normal SAFE exit/resource footers. All
original Crystal controls must pass before the candidate is invoked. Failures
are collected for the full stage; caches and executables are removed on exit.

Run `python3 run.py --self-test` to validate the packet without invoking a
compiler. Run `ORIGINAL_CRYSTAL_BIN=/path/to/crystal python3 run.py /path/to/adamas`
for the differential test. `ADAMAS_ROOT` and `ADAMAS_RUN_SAFE` may select another
checkout or SAFE runner. A default original compiler is resolved as `crystal`
on `PATH`.
