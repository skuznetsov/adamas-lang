# Crystal V2 Compiler

**A ground-up redesign of the Crystal compiler focused on developer experience, performance, and maintainability.**

---

## Vision

Crystal combines Ruby's expressiveness with static typing and native performance. The current compiler has architectural limitations that impact the development experience:

- **Slow compilation times** - Full recompilation on small changes
- **Limited incremental compilation** - No fine-grained dependency tracking
- **Poor LSP experience** - Slow response times for large files
- **Monolithic architecture** - Tight coupling between phases

**Crystal V2 aims to match Go's developer experience while keeping Crystal's superior language design.**

---

## Current State (May 2026)

### What is ready to try

The **Crystal V2 LSP server is the most stable part of the project today**.
It has a focused regression suite and is usable through the VS Code extension
or through `adamas tool lsp` when pointed at a built LSP server.

The **compiler/codegen pipeline is still beta**. It is useful for experiments,
no-prelude oracles, reduced repros, and bootstrap work, but it is not yet a
drop-in replacement for the production Crystal compiler. Expect codegen and
self-hosting bugs, especially around generated-stage compilers.

### Bootstrap Status

The compiler is in active bootstrap. Stage1 can build a generated stage2
compiler, but the generated compiler is not yet stable enough for a clean
stage2/stage3 cycle.

| Stage | Status | Time |
|-------|--------|------|
| Stage1 (original Crystal → V2) | Working, --release | ~7.5 min |
| Stage2 (V2 → V2) | Builds successfully | ~3 min |
| Stage2 running | Still unstable on broader full-prelude compilation | In progress |
| Stage3 (stage2 → V2) | Blocked by stage2 stability | Pending |

**LSP regression suite:** 254 examples, passing in the latest local gate.
**Compiler regression tests:** focused bootstrap/codegen guards are used as the
main near-term gate; full self-hosting is still being hardened.

### Pipeline

```
Crystal Source (.cr)
        │
        ▼
   ┌─────────┐
   │  Parser  │    Parallel file loading, VirtualArena, error recovery
   │(frontend)│    100% parity (2152/2152 tests, 0 failures) with original Crystal parser
   └────┬─────┘
        │  AST (typed nodes in arena pools)
        ▼
   ┌─────────┐
   │   HIR   │    ast_to_hir.cr (74K lines)
   │ Lowering│    Type registration, method resolution, RTA, monomorphization
   └────┬─────┘
        │  HIR Functions (SSA-like, typed)
        ▼
   ┌─────────┐
   │   MIR   │    hir_to_mir.cr (5.5K lines)
   │ Lowering│    SSA transformation, union dispatch, field access, casts
   └────┬─────┘
        │  MIR Functions (SSA, low-level)
        ▼
   ┌─────────┐
   │  LLVM   │    llvm_backend.cr (19K lines)
   │ Backend │    LLVM IR text emission, 8 parallel workers
   └────┬─────┘
        │  .ll file → llc → .o → ld
        ▼
   Native Binary
```

### Key Numbers

- **~120K lines** of compiler code (core pipeline)
- **~2,700 MIR functions** for hello world
- **~31,300 MIR functions** for self-compilation (stage2)
- **254** LSP regression examples passing in the latest local gate
- **570+** regression scripts and fixtures for compiler/bootstrap work
- **3,400+** git commits

---

## Architecture

### V2 ABI: Struct-as-Pointer

V2 heap-allocates ALL Crystal structs (unlike original Crystal which inlines them). This simplifies the ABI — every value is a pointer — but requires careful handling:

- **Classes:** Heap-allocated with 4-byte type_id header (offset 0), then fields
- **Structs:** Heap-allocated WITHOUT type_id header, fields start at offset 0
- **Unions:** All-reference unions (classes + Nil) stored as nullable pointer (8 bytes). Mixed unions use tagged layout: `{ i32 type_id, [N x i32] payload }`
- **Field storage:** Struct-typed fields store a pointer (8 bytes) regardless of inline size

### Method-Level RTA (Reachability)

V2 uses supply-driven compilation with RTA filtering:
- Register ALL methods from source → filter by reachability → only lower reachable ones
- Virtual dispatch tables built from RTA-discovered call targets
- Result: ~3,000 MIR functions for hello world (vs ~2,300 in original Crystal)

### Memory Management

Reference counting with per-type destructors:
- `rc_inc`/`rc_dec` at all persistent stores (FieldSet, ClassVarSet, PointerStore, etc.)
- Per-block cleanup: rc_dec owned Call results at block end
- Sentinel-safe, null-safe rc operations
- `@[Acyclic]` annotation for self-referencing types

### Parser & Arena System

- **VirtualArena:** Zero-copy multi-file AST management
- **PageArena:** Page-based allocation for large parse trees
- **AstArena:** Per-file arena with typed node storage
- **ArenaLike:** Union type for arena dispatch (`AstArena | VirtualArena | PageArena`)

---

## Build & Run

```bash
# Build V2 compiler (stage1) from original Crystal
scripts/build_stage1_original_release.sh /path/to/stage1

# Build stage2 (V2 compiles itself)
scripts/build_stage2_release.sh /path/to/stage1 /path/to/stage2

# Compile a program
/path/to/stage1 my_program.cr -o my_program

# Run safely (monitors FDs and memory)
scripts/run_safe.sh ./my_program 5 512

# Run regression tests
bash regression_tests/run_all.sh /path/to/stage1 8

# Quick debug build for fast iteration
crystal build src/adamas.cr -o bin/adamas --error-trace

# No-prelude oracle for fast debugging
bin/adamas test.cr --no-prelude -o test_bin
```

## Language Server

The LSP server is the recommended entry point for new users who want to try the
project without depending on compiler bootstrap stability.

```bash
# Build the standalone LSP server
./build_lsp.sh

# Or build the compiler and launch the sibling LSP server through tool mode
crystal build src/adamas.cr -o bin/adamas --error-trace
bin/adamas tool lsp
```

The VS Code extension lives in `vscode-extension/`. By default it discovers
`crystal2` on `PATH` and launches `crystal2 tool lsp`. If that is not
available it tries `adamas tool lsp`, then `adamas_lsp`. The extension
settings override discovery:

```json
{
  "crystalv2.lsp.serverPath": "/path/to/crystal2",
  "crystalv2.lsp.serverArgs": ["tool", "lsp"]
}
```

Current LSP coverage includes hover, definition, references, completion,
signature help, document symbols, folding, semantic tokens, inlay hints,
formatting, rename, and call hierarchy.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `CRYSTAL_V2_DUMP_LAYOUTS=Pattern` | Dump class field layouts to stderr |
| `CRYSTAL_V2_STOP_AFTER_PARSE=1` | Stop after parsing (for stage2 debugging) |
| `CRYSTAL_V2_EAGER_HIR=1` | Disable lazy HIR lowering |
| `CRYSTAL_V2_DEBUG_FIXUP=1` | Trace class ivar fixup |
| `CRYSTAL_PATH=path` | Override bundled stdlib path |

---

## Known Issues & Bug Patterns

### V2-Specific

- **Struct field storage:** V2 heap-allocates structs, so FieldGet always loads a pointer. Never skip load for struct types.
- **Union type sizing:** HIR and LLVM must agree on union classification (all-ref vs tagged). Generic struct instantiations (Slice(UInt8), etc.) are NOT all-ref because V2 structs lack runtime type headers.
- **Large struct fields:** `field_storage_size` only upgrades structs < pointer_size to pointer size. Structs > 8 bytes keep their inline size (tracked as future fix).
- **Closure capture:** V2 closure codegen can lose `self` reference — closures capturing `self` may get NULL.
- **kqueue FD leak:** Thread#scheduler reads nil → infinite Scheduler/EventLoop/kqueue() creation.

### Stage2 Bootstrap

- Stage2 binary crashes deterministically during `register_lib` → `with_resolved_body_arena`
- Root cause: Array buffer overflow in `macro_literal_texts_from_raw` (heap corruption)
- Previously fixed: DefNode allocation overflow (union type sizing mismatch between HIR and LLVM)

---

## Project Structure

```
adamas_repo/
├── src/
│   ├── adamas.cr              # Entry point
│   └── compiler/
│       ├── cli.cr                 # CLI, file loading, compilation orchestration
│       ├── frontend/              # Lexer, Parser, AST, Arena system
│       │   ├── parser.cr          # 16K lines, parallel parsing
│       │   ├── ast.cr             # Typed AST nodes, ExprId, ArenaLike
│       │   ├── lexer.cr           # Token generation
│       │   └── small_vec.cr       # Stack-optimized collections
│       ├── hir/                   # High-level IR
│       │   ├── ast_to_hir.cr      # 74K lines — the core lowering engine
│       │   └── hir.cr             # HIR data structures
│       ├── mir/                   # Mid-level IR
│       │   ├── hir_to_mir.cr      # HIR → MIR SSA transformation
│       │   ├── llvm_backend.cr    # 19K lines — LLVM IR text emission
│       │   └── mir.cr             # MIR data structures
│       ├── semantic/              # Symbol table, type inference
│       └── lsp/                   # Language Server Protocol
├── regression_tests/              # 87 individual + 20 combined tests
│   ├── run_all.sh                 # Test runner (parallel)
│   ├── combined/                  # Grouped multi-feature tests
│   └── stage2_*.sh               # Stage2-specific reproduction scripts
├── scripts/
│   ├── build_stage1_original_release.sh
│   ├── build_stage2_release.sh
│   └── run_safe.sh               # Safe binary runner (FD/memory limits)
├── examples/                      # Benchmark programs
└── CLAUDE.md                      # AI assistant instructions
```

---

## Critical Rules for Development

1. **NEVER modify stdlib files** — must be 100% compatible with original Crystal stdlib at `../crystal/src`
2. **Always use `scripts/run_safe.sh`** for running test binaries — prevents FD/memory exhaustion
3. **Use `--no-prelude` oracles** for fast debugging iteration (seconds vs minutes)
4. **Check original Crystal compiler** at `../crystal/src/compiler/crystal/codegen/` when in doubt
5. **Commit working fixes immediately** — one feature/bugfix per commit
6. **Create regression scripts** for every bug found
7. **Clean up temp files** in /tmp/ and .codex_artifacts/

---

## Team

**Lead:** Sergey Kuznetsov — Architecture & direction

**AI Contributors:**
- Claude (Anthropic) — Architecture, implementation, debugging, bootstrap stabilization
- GPT-5.4 (OpenAI) — Parser hardening, stage2 oracle investigation, regression test infrastructure
- Codex (OpenAI) — Specialized investigation tasks

---

## License

MIT (same as Crystal)
