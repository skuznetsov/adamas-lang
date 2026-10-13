#!/usr/bin/env bash
# Regression: a block passed to a user yield-def that contains `next` becomes a
# raw block thunk whose captures live in global closure cells. For an untyped
# `ann = nil` capture the cell is `Nil | T`, but writes inside the thunk stored
# the raw T without a union wrap, so the parent read back nil after the call.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure_cell_union_write_coerce_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
build() {
  local case_name="$1"; shift
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" "$@" -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
}

check_exit() {
  local case_name="$1" expected="$2"
  build "$case_name" --no-prelude || return 0
  if ! grep -q "^\[EXIT: $expected\]" "$WORK_DIR/$case_name.run.log"; then
    echo "FAIL[$case_name]: expected exit $expected" >&2
    cat "$WORK_DIR/$case_name.run.log" >&2
    status=1
  fi
}

check_stderr() {
  local case_name="$1" expected="$2"
  build "$case_name" || return 0
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDERR ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/n1.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
def each_w(n : Int32, &)
  i = 0
  while i < n
    yield i
    i += 1
  end
end
def q6(n : Int32, key : Int32) : Int32
  ann = nil
  each_w(n) do |pp|
    next if pp < 0
    ann = key
  end
  a = ann
  a ? a : -1
end
def q7(n : Int32, key : Int32) : Int32
  ann = nil
  other = 0
  each_w(n) do |pp|
    next if pp < 0
    ann, other = key, pp
  end
  a = ann
  a ? a + other : -1
end
def pair(a : Int32, b : Int32) : {Int32, Int32}
  {a, b}
end
def q11(n : Int32, key : Int32) : Int32
  ann = nil
  other = 0
  each_w(n) do |pp|
    next if pp < 0
    ann, other = pair(key, pp + 1)
  end
  a = ann
  a ? a + other : -1
end
LibC.exit(q6(1, 5) + q7(1, 2) + q11(1, 3))
CR
check_exit n1 11

cat >"$WORK_DIR/p1.cr" <<'CR'
def each_p(arr : Array(Int32), &)
  arr.each { |x| yield x }
end

def q3(args : Array(Int32), key : String)
  ann = nil
  each_p(args) do |pp|
    next if pp < 0
    ann = key
  end
  STDERR.puts "q3 #{ann.inspect}"
end

q3([7], "a")
q3([-1], "b")
STDERR.flush
CR
check_stderr p1 'q3 "a"
q3 nil'

if [ "$status" -ne 0 ]; then
  echo "FAIL: closure-cell write lost union wrap" >&2
  exit 1
fi
echo "PASS: closure-cell union writes OK"
