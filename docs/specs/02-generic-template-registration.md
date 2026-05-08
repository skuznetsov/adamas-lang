# Generic Template Registration Contract

> Status: Draft v0.1, 2026-05-08.
> Scope: generic class/module/proc/container registration and nested body scan.

## 1. Purpose

Generated-stage bootstrap spends most of its time exposing generic edge cases:
nested modules, tuples, hashes, arrays, procs, iterators, macro-generated
containers, and stdlib templates.

This document defines what a valid generic-template registration strategy may
and may not do.

## 2. No Arbitrary Depth Caps

The compiler MUST NOT fix generic, proc, block, tuple, array, hash, iterator,
or nested-container bugs by adding arbitrary depth caps.

Real Crystal programs may contain deeply nested shapes. A guard MAY reject a
known non-demand pattern, but production code MUST preserve demanded deep
shapes.

Acceptable controls:

- demand-driven reachability;
- owner/idempotence checks;
- source/provider trust boundaries;
- arena provenance validation;
- explicit cycle detection keyed by semantic identity.

Unacceptable controls:

- "stop after depth N" as a correctness fix;
- suppressing all nested body scans for generic templates;
- broad regex filtering of generated names without semantic ownership proof.

## 3. Registration Identity

Each generic template and specialization MUST have a stable semantic identity:

- owner canonical name;
- template name;
- type parameters;
- source definition identity;
- specialization argument identity when applicable.

String rendering is not identity. Names such as `Iterator::`,
`Steppable::`, or repeated `Indexable::Indexable::...` are bug signatures, not
valid canonical identities.

## 4. Nested Types in Generic Owners

Nested types inside generic owners MUST be recorded under the canonical owner
without duplicating owner segments. A child name already qualified under the
owner MUST be preserved rather than joined again.

This contract shares the same namespace invariant as
`01-hir-name-resolution.md`, but generic owners add specialization context.

## 5. Body Scan Policy

Generic-template body scanning is allowed only when all are true:

1. The scan is demanded by a reachable call, type query, macro expansion, or
   registration dependency.
2. The scan key includes enough identity to prevent self-recursive reentry.
3. The scan does not cross from a trusted source/provider boundary into raw
   generated-stage slices.
4. The scan has a narrow falsifier.

Body scanning MUST NOT be used as a broad pre-scan just because a generated
stage is missing metadata. That pattern has already been refuted.

## 6. Acceptance Signals

A generic-template change is not accepted by "full compiler got farther" alone.
It needs at least one narrow guard that proves the intended invariant.

Examples of useful guard families:

- qualified namespace does not duplicate under generic owners;
- generic container names never become empty owner suffixes;
- demanded nested types remain visible after self-wrapper filtering;
- produced stage passes the guard, not only the host-built compiler.
