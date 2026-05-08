# CLI Output Contract

> Status: Draft v0.1, 2026-05-08.
> Scope: compiler CLI modes, output side effects, and post-LLVM tail behavior.

## 1. Purpose

Several recent frontiers reached valid HIR/MIR/LLVM emission and then crashed
after LLVM finalized output. That is a different contract family from callee
selection or LLVM spelling.

This document defines the output-mode boundary so future fixes do not paper
over CLI tail crashes by changing semantic lowering.

## 2. Compile Modes

The CLI MUST keep these modes behaviorally separate:

- `--emit hir`
- `--emit mir`
- `--emit llvm-ir`
- `--no-link`
- normal binary output
- `--no-prelude`
- check-only or stop-after phase debug modes

Passing an earlier emit mode does not prove the later mode. A fix for binary
output MUST be verified with binary output. A fix for LLVM spelling MAY stop at
`--emit llvm-ir --no-link`.

## 3. Output Side Effects

Output side effects include:

- opening and closing output files;
- writing `.ll`, `.o`, and final binaries;
- invoking LLVM target/object emission;
- invoking the linker;
- restoring CLI compile context after a phase raises or returns;
- preserving the process exception state.

These side effects are part of the CLI contract. They MUST NOT corrupt global
exception state, output path state, current compile context, or file handles.

## 4. Post-LLVM Tail

When LLVM finalization succeeds and the process then exits 139, the next fix
MUST localize the crash to one of:

- LLVM object emission tail;
- output file flush/close;
- linker invocation setup;
- CLI return path;
- outer rescue / exception-state handling;
- generated-stage runtime teardown.

Changing HIR/MIR lowering to avoid this path is a symptom patch unless a narrow
falsifier proves the lowering caused the tail crash.

## 5. Required Guards

A post-LLVM tail fix SHOULD add or update guards for at least two adjacent
modes:

1. `--emit llvm-ir --no-link` succeeds and the emitted IR passes its semantic
   oracle.
2. Normal binary output for the same reducer succeeds or fails at a clearly
   later expected boundary.

Produced binaries created by the compiler MUST still be run only through
`scripts/run_safe.sh`.

## 6. Current Frontier

As of LM-559, produced `s2` can emit valid no-prelude LLVM IR for the
`Exception::CallStack.skip("x")` static-call reducer, and `llc` accepts that
IR. Normal no-prelude binary output for the same reducer still exits 139 after
LLVM finalizes output.

That frontier belongs here, not in HIR name resolution or MIR static-call ABI,
unless fresh evidence contradicts the split.
