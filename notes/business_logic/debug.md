# Debug Hooks and Tracing

## HIR Debug Hooks
- File: `src/compiler/hir/debug_hooks.cr`
- Build: `crystal build -Ddebug_hooks src/adamas.cr -o bin/adamas_debug`
- Run:
  - `ADAMAS_DEBUG_HOOKS=1 ./bin/adamas_debug <file>`
  - `ADAMAS_DEBUG_HOOKS_FILTER=call.class_receiver.unresolved` to narrow output.

## Driver Trace
- `ADAMAS_DRIVER_TRACE=1` enables driver stage logs.

## LSP Debug
- `LSP_DEBUG=1` for stderr logs.
- `LSP_DEBUG_LOG=/path` for persistent logs.
