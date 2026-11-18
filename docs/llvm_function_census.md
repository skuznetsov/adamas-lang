# LLVM Function Census

This workflow compares function inventories emitted by original Crystal and
Adamas without treating their raw symbol spellings as the same identity.

## Produce a comparable pair

Use the same source, optimization level, debug mode, and prelude mode for both
compilers. Keep compiler/source digests with the reports. For a small source:

```bash
CRYSTAL_CACHE_DIR=/private/tmp/adamas_census_crystal_cache \
  crystal build /path/to/probe.cr --prelude=empty --no-debug -O0 \
  --single-module --emit=llvm-ir -o /private/tmp/original_probe

scripts/run_safe.sh /path/to/adamas 120 4096 \
  /path/to/probe.cr --no-prelude --emit llvm-ir --no-link \
  -o /private/tmp/adamas_probe
```

Never compare files from different source corpora as an authoritative semantic
pair. Such a run is useful only as a parser/performance smoke.

## Compare semantic inventories

```bash
python3 scripts/compare_llvm_functions.py \
  --original-ll /private/tmp/original_probe.ll \
  --adamas-ll /private/tmp/adamas_probe.ll \
  --out-dir /private/tmp/llvm_function_census
```

The comparator parses original Crystal symbols structurally and then applies
Adamas' forward mangler. Reverse demangling is display-only because the Adamas
token alphabet is not prefix-free.

Important report boundaries:

- `matches.tsv` contains authoritative forward-name matches.
- `provisional_matches.tsv` contains `$arity`, splat, named, and related ABI
  shape hints that the original symbol alone cannot prove.
- `collisions.tsv` retains receiver/implementation fanout and cardinality.
- `abi_conflicts.tsv` compares textual LLVM type shapes. A named-type spelling
  mismatch is a diagnostic, not by itself a proof of incompatible layouts.
- `original_only.tsv` and `adamas_only.tsv` are inventories, not automatic bug
  lists. Runtime helpers, intrinsics, and alternate lowering strategies require
  classification before a missing/extra claim.

## Triage static reachability

Run the reachability census on both inputs:

```bash
python3 scripts/llvm_function_reachability.py \
  --ll /private/tmp/original_probe.ll \
  --out-dir /private/tmp/original_reachability

python3 scripts/llvm_function_reachability.py \
  --ll /private/tmp/adamas_probe.ll \
  --out-dir /private/tmp/adamas_reachability
```

This pass follows textual function-body references from Crystal entry points
and conservatively roots function targets found in global initializers. It also
tracks source callers, vdispatch callers, linkage, declarations, and function
header references such as `personality` routines.

Reachability is triage, not linker-equivalent liveness. Indirect calls, aliases,
ifuncs, runtime table interpretation, and malformed multiline headers can still
change the answer. Do not delete a function based only on `reachable=false`;
first prove the demand path or runtime table cannot consume it.

## Fast verification

```bash
CRYSTAL_CACHE_DIR=/private/tmp/adamas_census_spec_cache \
  crystal spec spec/llvm_function_census_spec.cr \
  spec/llvm_function_reachability_spec.cr

PYTHONPYCACHEPREFIX=/private/tmp/adamas_census_pycache \
  python3 -m py_compile \
  scripts/compare_llvm_functions.py \
  scripts/llvm_function_reachability.py
```
