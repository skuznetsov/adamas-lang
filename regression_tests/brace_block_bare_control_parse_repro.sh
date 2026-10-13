#!/usr/bin/env bash
# Regression: brace blocks whose body is a bare control keyword
# (`wrap { break }`, `{ next }`, `{ return }`) must parse. The parser used
# to take `}` as the control value; error recovery then silently dropped
# the whole call (exit 0, missing output). Also checks `break; stmt`.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brace_block_bare_control_parse_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
check() {
  local case_name="$1" expected="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" --no-prelude -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDOUT ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/c1.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
def wrap
  LibC.printf("in-wrap\n")
  yield
  LibC.printf("not-here\n")
end
def each2
  yield 1
  yield 2
end
def ret_in_block : Int32
  wrap { return 7 }
  0
end
def bare_ret
  wrap { return }
  LibC.printf("not-here-ret\n")
end
def brk
  wrap { break }
  LibC.printf("after-brk\n")
end
def nxt
  each2 { |v| LibC.printf("v%d\n", v); next }
end
def semi
  i = 0
  while true
    i += 1
    break; LibC.printf("dead\n")
  end
  LibC.printf("semi-i%d\n", i)
end
brk
nxt
bare_ret
LibC.printf("ret%d\n", ret_in_block)
semi
CR
check c1 'in-wrap
after-brk
v1
v2
in-wrap
in-wrap
ret7
semi-i1'

if [ "$status" -ne 0 ]; then
  echo "FAIL: brace-block bare control keyword dropped or mis-parsed" >&2
  exit 1
fi
echo "PASS: brace-block bare control keywords parse correctly"
