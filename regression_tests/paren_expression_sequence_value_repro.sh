#!/usr/bin/env bash
# Regression: a parenthesized expression sequence `(a; b)` (or `(a\nb)`) is
# Crystal's Expressions(:paren) whose value is the LAST expression. The parser
# folded `;`-separated grouping elements into a TupleLiteral, so `c = (1; 2)`
# was typed Tuple(Int32, Int32) and `c == 2` hit a bodyless Tuple#==. The
# newline-separated form stopped after the first statement (`c = 1`).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/paren_expression_sequence_value_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/ps.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def side(x : Int32) : Int32
  x &* 10
end

code = 0
c = (1; 2)
code |= 1 unless c == 2
d = (x = 'x'; x)
code |= 2 unless d == 'x'
e = (side(1)
     side(4))
code |= 4 unless e == 40
f = ((y = 3; y &+ 1))
code |= 8 unless f == 4
t = (5)
code |= 16 unless t == 5
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 4096 \
    "$WORK_DIR/ps.cr" --no-prelude -o "$WORK_DIR/ps" >"$WORK_DIR/ps.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/ps.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/ps" 5 512 >"$WORK_DIR/ps.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/ps.run.log"; then
  echo "FAIL: runtime result (exit code bitmask: 1=(1;2) 2=char seq 4=newline seq 8=nested 16=single)" >&2
  grep '^\[EXIT' "$WORK_DIR/ps.run.log" >&2 || tail -10 "$WORK_DIR/ps.run.log" >&2
  exit 1
fi
echo "PASS"
