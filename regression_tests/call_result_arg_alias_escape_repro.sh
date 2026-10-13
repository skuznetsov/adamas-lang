#!/usr/bin/env bash
# Regression: an inline value allocation (tuple / NamedTuple literal, packed
# `**opts`) passed to a call whose result escapes must escape too.
# EscapeAnalyzer#propagate_backwards had no Call arm, so `wrap({n, 5})` with
# `def wrap(x); x; end` left the literal StackLocal -> `alloca` -> the caller
# returned a pointer into its own dead frame (use-after-return).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/call_result_arg_alias_escape_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/ae.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def wrap(x)
  x
end

def tr2(**metadata)
  metadata
end

def g(n : Int32)
  wrap({n, 5})
end

def h(n : Int32)
  wrap({a: n, b: 6})
end

def k(n : Int32)
  tr2 a: n, b: 9
end

def clobber(a : Int32, b : Int32, c : Int32, d : Int32) : Int32
  t = {a, b, c, d}
  u = {a: d, b: c}
  t[0] + u[:a]
end

x = g(3)
y = h(4)
z = k(8)
w = clobber(100, 200, 300, 400)
code = 0
code |= 1 unless x[0] == 3 && x[1] == 5
code |= 2 unless y[:a] == 4 && y[:b] == 6
code |= 4 unless z[:a] == 8 && z[:b] == 9
code |= 8 unless w == 500
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/ae.cr" --no-prelude -o "$WORK_DIR/ae" >"$WORK_DIR/ae.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/ae.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/ae" 5 512 >"$WORK_DIR/ae.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/ae.run.log"; then
  echo "FAIL: call-result alias left an escaping value allocation on the stack" >&2
  cat "$WORK_DIR/ae.run.log" >&2
  exit 1
fi
echo "PASS: escaping call results make their value-allocation args escape"
