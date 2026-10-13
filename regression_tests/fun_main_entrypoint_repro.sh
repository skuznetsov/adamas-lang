#!/usr/bin/env bash
# Regression: a top-level `fun main` (stdlib crystal/main.cr: `fun main` ->
# Crystal.main -> init_runtime) was lowered under a MANGLED name because the
# unmangled override was set after `lookup_name` had been fixed in lower_def.
# RTA (rooted at "main") then pruned it, the backend emitted its native
# `main -> __adamas_main`, and Crystal.init_runtime never ran: Fiber.@@fibers
# stayed uninitialized and `[1].inspect` (exec_recursive -> Fiber.current)
# segfaulted. Expected: exit 7 from Crystal.main, never 3 from top-level code.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fun_main_entrypoint_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/fm.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

module Crystal
  def self.main(argc : Int32, argv : UInt8**) : Int32
    LibC.exit(argc > 0 ? 7 : 9)
    0
  end
end

fun main(argc : Int32, argv : UInt8**) : Int32
  Crystal.main(argc, argv)
end

LibC.exit(3)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 4096 \
    "$WORK_DIR/fm.cr" --no-prelude -o "$WORK_DIR/fm" >"$WORK_DIR/fm.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/fm.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/fm" 5 512 >"$WORK_DIR/fm.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 7\]' "$WORK_DIR/fm.run.log"; then
  echo "FAIL: user fun main was not the entrypoint" >&2
  tail -5 "$WORK_DIR/fm.run.log" >&2
  exit 1
fi
echo "PASS"
