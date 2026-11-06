# Exact selected named-call forall bindings

The 12 main cases require stock Crystal qualification before Adamas. They cover
formal-slot projection across skipped defaults and external labels, same-spelled
owner/method type variables, consistent repeated method variables, reversed named
class/instance arguments, and strict incompatible argument rejections. Positive
cases execute and compare exact output; negative cases require semantic errors
and no executable.

The unknown `paylod` label is stock-qualified in `open_companions` but excluded
from candidate success: the old compiler and the transport candidate both accept
it and the resulting executable aborts. This is a separate named-label admission
bug. Callback-inferred defaults and ordinary keyword-rest body identity are also
outside this slice.

Run `regression_tests/source_named_forall_contract_repro.sh /path/to/adamas`.
Set `ORIGINAL_ONLY=1` to qualify the stock oracle without running Adamas.
