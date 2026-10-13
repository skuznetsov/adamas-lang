#!/usr/bin/env bash
# Regression: a caller block inlined through a two-level inline yield
# (del -> outer -> each_x) whose body names a caller variable (`char`) that is
# also a block param of the intermediate callee (`each_x do |char|`). The yield-site
# caller-locals refresh only masked the innermost callee-name set, which inside the
# intermediate block body is empty, so `char` resolved to the callee block param.
# Stdlib hit: String#delete(Char) returned "" (`delete { |c| c == char }` inside
# `each_char do |char|`), so the S2 lexer typed every literal as Int32.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inline_yield_caller_block_name_collision_repro.XXXXXX")"
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
def each_x(n : Int32, &)
  i = 0
  while i < n
    yield i
    i += 1
  end
end
def outer(&)
  cnt = 0
  each_x(5) do |char|
    cnt += 1 unless yield char
  end
  cnt
end
def del(char : Int32) : Int32
  outer { |my_char| my_char == char }
end
def del_local(k : Int32) : Int32
  char = k + 1
  outer { |my_char| my_char == char }
end
def outer2(&)
  cnt = 0
  each_x(4) do |cnt2|
    cnt += 1 if yield cnt2
  end
  cnt
end
def del_cnt(cnt : Int32) : Int32
  outer2 { |v| v < cnt }
end
LibC.exit((del(2) == 4 ? 0 : 1) + (del_local(1) == 4 ? 0 : 2) + (del_cnt(3) == 3 ? 0 : 4))
CR
check_exit n1 0

cat >"$WORK_DIR/p1.cr" <<'CR'
STDERR.puts "12_34".delete('_')
STDERR.puts "a-b-c".delete('-')
STDERR.puts "9_223_372_036_854_775_807".delete('_').to_i64?.inspect
STDERR.flush
CR
check_stderr p1 '1234
abc
9223372036854775807'

if [ "$status" -ne 0 ]; then
  exit 1
fi
echo "PASS: inline-yield caller block name collision OK"
