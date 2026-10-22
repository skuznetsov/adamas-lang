# Proc constructor receiver ownership fixtures

This narrow regression contains 15 positive runtime cases and one semantic rejection. Thirteen positives come from the separately retained 20-case receiver probe; the other two and the negative discriminator are the original-first default/splat result-edge probes. Sources, expected stdout, and the negative marker are preserved byte-for-byte.

The matched HEAD `12167` versus atomic `12168` comparison changed only `rooted_proc_base_shadowed_by_owner_alias` from failing to passing. The 12 cases that already passed stayed passing; seven failures in the broader 20-case probe remained. This suite records the receiver ownership fix alongside the two independent default/splat edge controls.

The broader 20-case probe remains unchanged and exposes unresolved source-kind and Proc-call admission gaps, including nested captures. Its frozen runner and fixtures are retained under `/Users/sergey/Projects/Adamas/sol_help_20261012/OUT/lavin12164_proc_fact_differential_guard/`; they are not a dependency of this regression. This narrower suite does not redefine that broader result. Seven failures and the separate local `typeof` result gap remain open in `docs/compiler_architecture_sdd.md`, section 6.3.
