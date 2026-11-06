# Known-open candidate cases

These two fixtures are stock-qualified controls for `self.new` returning class-object or union values. The current candidate is known to fail both, so they are excluded from the default 27-case candidate gate and are never counted as candidate passes. The harness always runs them on stock Crystal before candidate execution; `RUN_KNOWN_OPEN=1` optionally exercises them on the candidate and may fail.
