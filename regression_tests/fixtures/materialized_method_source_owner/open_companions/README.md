# Open inherited named-default dispatch obligation

Crystal 1.22.1 prints `A`. Both HEAD 0e29163b (35q2966) and the
materialized-source candidate 35q2958 print `B`. The intermediate strict
candidate 35q2948 rejects earlier because the same target has an orphan
arena (35q2962). Removing that orphan does not close virtual override
selection for a named-only default. This companion is stock-qualified and
excluded from candidate success; do not change its expected result to `B`.

All compiler and executable probes must use `scripts/run_safe.sh`. Preserve
the inherited named-default override obligation when changing source binding,
virtual override collection, call-shape projection, or body materialization.
