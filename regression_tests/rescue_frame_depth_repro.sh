#!/usr/bin/env bash
# Regression: rescue regions may nest deeper than any fixed bound.
#
# Rescue frames lived in a global `[64 x jmp_buf]` array indexed by a depth
# counter with no bound check. A recursive method whose body is a begin/rescue
# keeps one frame active per activation, so recursion past 64 levels made
# setjmp write past the array, clobbering the depth counter and the current
# exception pointer that follow it. Frames are now records in the protecting
# function's own stack frame, linked innermost-first.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rescue-frame-depth.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
# Every activation keeps its rescue frame active across the recursive call.
def walk(n : Int32) : Int32
  begin
    n == 0 ? 0 : walk(n - 1) + 1
  rescue
    -1
  end
end

# The raise at the bottom crosses every active frame, one rethrow at a time.
def dive(n : Int32) : Int32
  begin
    if n == 0
      raise ArgumentError.new("bottom")
    end
    dive(n - 1) + 1
  rescue e
    raise e
  end
end

def guarded(n : Int32) : Int32
  begin
    dive(n)
  rescue e : ArgumentError
    STDERR.puts "caught #{e.message} at #{n}"
    n
  end
end

STDERR.puts walk(100)
STDERR.puts walk(2000)
STDERR.puts guarded(10)
STDERR.puts guarded(70)
STDERR.puts guarded(1000)
begin
  raise ArgumentError.new("after")
rescue e : ArgumentError
  STDERR.puts "caught #{e.message}"
end
STDERR.puts "done"
CR

expected='100
2000
caught bottom at 10
10
caught bottom at 70
70
caught bottom at 1000
1000
caught after
done'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: rescue depth program did not compile" >&2
  strip < "$WORK_DIR/build.log" | tail -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: rescue depth program exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: rescue frames nest past any fixed depth"
