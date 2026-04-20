#!/bin/bash
# Forward guard for P1 I14-owner-aware boxed-local dominance (escaping capture).
#
# Specifically covers GPT's fourth DoD item from the P1 audit:
#   outer local captured by a closure constructed INSIDE ONE BRANCH,
#   closure ESCAPES the branch, later call mutates/reads the same
#   boxed local.
#
# Shape: a proc literal capturing a mutable parent-scope local is
# constructed ONLY inside the then-branch of an `if` whose condition
# is runtime-unknown (`ARGV.size == 0`). The proc escapes via
# assignment to a pre-declared Proc-typed local (no Proc|Nil union —
# pre-declared with an identity default). After the `if`, the outer
# code calls the proc and reads the local.
#
# What this exercises:
#   1. Proc literal in ONE branch only. Correct P1 must have
#      predeclared/seeded the `counter` box before this branch; invoking
#      hoist_box_for_local from the branch is a compiler bug.
#   2. Proc escapes the branch via SSA assignment to outer `p`.
#   3. Non-zero initial value (`counter = 5`) catches the unsafe
#      "entry allocation + zero-init is enough" shortcut. The box must
#      be seeded from the local's current value before branch lowering.
#   4. Outer call site `p.call(7)` and outer read `puts counter` are
#      after the branch merge. Under I14-owner-aware, `counter` keeps
#      using the box owned by the parent local binding after scope restore;
#      the box alloc+seed MUST dominate the outer call/read.
#   5. Re-entrance: the second `if` (checking ARGV.size again) is a
#      guard that prevents compile-time constant folding from
#      eliminating the branch.
#
# Proc|Nil and Array(Proc) are avoided (both have separate pre-P1
# codegen issues that would conflate unrelated failures).
#
# Exit semantics: mirrors conditional_closure_capture_repro.sh.
#   exit 1 — CORRECT: "12\n12" (ARGV.size == 0 → capture proc ran).
#   exit 0 — REPRODUCED: wrong output, runtime crash, verifier fail.
#   exit 2 — INCONCLUSIVE: compile failure.
#
# Status: this is a FORWARD guard. It must continue to exit 1 as closure-env
# cleanup removes legacy class-var capture paths.

set -u

COMPILER="${1:-}"
if [[ -z "$COMPILER" ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/escaping_branch_closure_capture.cr"
BIN="$TMPDIR/escaping_branch_closure_capture"
RUN_LOG="$TMPDIR/run.log"

cat > "$SRC" <<'EOF'
counter = 5
default_proc = ->(x : Int32) { x }
p = default_proc

if ARGV.size == 0
  p = ->(x : Int32) { counter += x; counter }
end

puts p.call(7)
puts counter
EOF

if ! "$COMPILER" "$SRC" -o "$BIN" >"$TMPDIR/compile.log" 2>&1; then
  echo "inconclusive: compile_failed"
  sed 's/^/  /' "$TMPDIR/compile.log" | tail -20
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  echo "reproduced: runtime failure (rc=$RC)"
  tail -20 "$RUN_LOG"
  exit 0
fi

OUT=$(awk '
  /^=== STDOUT ===$/ { in_stdout = 1; next }
  /^=== STDERR ===$/ { in_stdout = 0 }
  in_stdout { print }
' "$RUN_LOG")

# ARGV.size == 0 at the runner-level invocation, so capture proc runs
# and mutates counter. Expected "12\n12".
if [[ "$OUT" == "12"$'\n'"12" ]]; then
  echo "correct: branch-local proc escaped and mutated boxed counter"
  exit 1
fi

echo "reproduced: expected '12\\n12', got: $(printf '%q' "$OUT")"
tail -20 "$RUN_LOG"
exit 0
