#!/usr/bin/env bash
# Regression: `x = nil; while ..; x ||= Foo.new; ..; end` lost the loop value.
# The parser desugars `x ||= v` to `x = x || v`; loop-phi inference
# (collect_local_assignment_types) skipped every self-referential assignment,
# so the phi stayed Nil, `x || v` folded to an unconditional `Foo.new` and the
# exit value was Nil. In S2 this dropped `rescue_clauses` in
# Parser#parse_rescue_sections, so S3 lowered every begin/rescue without its
# rescue arms.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nil_init_or_assign_loop_phi_widen_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/oa.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class Box
  def initialize
    @n = 0
  end

  def add
    @n += 1
  end

  def n
    @n
  end
end

def tok(i : Int32) : Int32
  i < 2 ? 7 : 0
end

def or_assign(k : Int32) : Box?
  b = nil
  i = 0
  while i < k
    b ||= Box.new
    b.add
    i += 1
  end
  b
end

def or_assign_tuple : Tuple(Box?, Int32)
  b = nil
  i = 0
  while tok(i) == 7
    b ||= Box.new
    b.add
    i += 1
  end
  {b, 5}
end

code = 0
r = or_assign(2)
code |= 1 unless r && r.n == 2
code |= 2 unless or_assign(0).nil?
t, e = or_assign_tuple
code |= 4 unless t && t.n == 2 && e == 5
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/oa.cr" --no-prelude -o "$WORK_DIR/oa" >"$WORK_DIR/oa.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/oa.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/oa" 5 512 >"$WORK_DIR/oa.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/oa.run.log"; then
  echo "FAIL: nil-initialized loop local assigned via ||= lost its value" >&2
  cat "$WORK_DIR/oa.run.log" >&2
  exit 1
fi
echo "PASS: ||= inside a loop widens the nil-initialized loop phi"
