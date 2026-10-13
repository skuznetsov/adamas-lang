#!/usr/bin/env bash
# Regression: the return type of an unannotated def that forwards to an
# untyped-param def (`def g(n : Int32); wrap({n, 6}); end`) must follow the
# argument type of THAT call, not whichever `wrap` specialization was inferred
# first.
# Two roots:
#   1. Body return inference of a top-level def did not see the def's own
#      annotated params (no owner), so `wrap(n)` arg types were unknown.
#   2. Bare top-level calls answered from the base-name return caches
#      (`wrap` -> wrap$Int32) before the per-argument-type lookup.
# Symptom: h/k declared `-> Int32` while returning Tuple/NamedTuple (abort or
# garbage tuple reads); the callsite also leaked phantom `Tuple(n, 5)` types.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/untyped_wrapper_return_per_arg_type_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/uw.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def wrap(x)
  x
end

def g(n : Int32)
  wrap(n)
end

def h(n : Int32)
  wrap({n, 6})
end

def k(n : Int32)
  wrap({a: n, b: 7, c: 8})
end

def gt(n : Int32)
  wrap({n, 5})
end

def clobber(a : Int32, b : Int32, c : Int32, d : Int32) : Int32
  t = {a, b, c, d}
  u = {a: d, b: c}
  t[0] + u[:a]
end

code = 0
x = g(3)
y = h(4)
z = k(5)
code |= 1 unless x == 3
code |= 2 unless y[0] == 4 && y[1] == 6
code |= 4 unless z[:a] == 5 && z[:b] == 7 && z[:c] == 8
t = gt(9)
c = clobber(100, 200, 300, 400)
code |= 8 unless t[0] == 9 && t[1] == 5
code |= 16 unless c == 500
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/uw.cr" --no-prelude -o "$WORK_DIR/uw" >"$WORK_DIR/uw.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/uw.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/uw" 5 512 >"$WORK_DIR/uw.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/uw.run.log"; then
  echo "FAIL: untyped wrapper return collapsed to the first specialization" >&2
  cat "$WORK_DIR/uw.run.log" >&2
  exit 1
fi
echo "PASS: wrapper returns follow per-call argument types"
