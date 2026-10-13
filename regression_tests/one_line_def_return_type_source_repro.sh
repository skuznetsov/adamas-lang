#!/usr/bin/env bash
# Regression: one-line class methods `def a : Int32; @a; end` registered the
# return type "Int32; @a; end". def_explicit_return_type_from_source_in_arena
# ended the def header only at the first newline, so the body after `;` was
# read as part of the return type and call sites dispatched on a phantom type
# (STUB abort, exit 134). The header must also end at a top-level `;` or `#`.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/one_line_def_return_type_source_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/ol.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class Foo
  def initialize(@a : Int32); end
  def a : Int32; @a; end
  def b; @a + 1; end
  def c(x : Int32 = 2) : Int32; x + @a; end
  def d(ch : Char = ';') : Int32; @a + 3; end
  def e : Int32 # comment ; with : colon
    @a + 4
  end
end

def top : Int32; 3; end

f = Foo.new(5)
code = 0
code |= 1 unless f.a == 5
code |= 2 unless f.b == 6
code |= 4 unless top == 3
code |= 8 unless f.c == 7
code |= 16 unless f.d == 8
code |= 32 unless f.e == 9
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/ol.cr" --no-prelude -o "$WORK_DIR/ol" >"$WORK_DIR/ol.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/ol.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/ol" 5 512 >"$WORK_DIR/ol.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/ol.run.log"; then
  echo "FAIL: one-line def return type swallowed its body" >&2
  cat "$WORK_DIR/ol.run.log" >&2
  exit 1
fi
echo "PASS: one-line def header ends at the top-level semicolon"
