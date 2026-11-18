#!/usr/bin/env bash
# Regression: a typed rescue clause catches only the types it names.
#
# The last clause of a rescue chain was lowered as a catch-all even when it
# named a type, so `rescue e : ArgumentError` swallowed a KeyError and code
# after it ran with the wrong exception bound. A union clause
# `rescue e : KeyError | IndexError` was tested against the union's own type
# id, which no exception header carries; it only appeared to work because it
# was the last clause. Each variant is now tested, and an exception no clause
# matches is re-raised to the enclosing frame.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rescue-last-typed.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class MyErr < Exception
end

class SubArg < ArgumentError
end

# Single typed clause: a subclass matches, anything else propagates.
def f(k : Int32)
  begin
    case k
    when 0 then raise MyErr.new("m")
    when 1 then raise SubArg.new("s")
    when 2 then raise KeyError.new("k")
    else        raise IndexError.new("i")
    end
  rescue e : ArgumentError
    STDERR.puts "arg #{e.message}"
  end
end

# Union clause: either listed type matches.
def g(k : Int32)
  begin
    f(k)
  rescue e : KeyError | IndexError
    STDERR.puts "ki #{e.message}"
  end
end

# Two typed clauses, neither matches: the exception leaves the method.
def h(k : Int32)
  begin
    raise MyErr.new("h#{k}")
  rescue e : KeyError
    STDERR.puts "wrong key"
  rescue e : IndexError
    STDERR.puts "wrong index"
  end
end

begin
  g(1)
  g(2)
  g(3)
  g(0)
rescue e : MyErr
  STDERR.puts "outer #{e.message}"
end
begin
  h(5)
rescue e : MyErr
  STDERR.puts "outer #{e.message}"
end
STDERR.puts "done"
CR

expected='arg s
ki k
ki i
outer m
outer h5
done'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|run_safe\.sh: ' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: typed rescue program did not compile" >&2
  strip < "$WORK_DIR/build.log" | tail -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: typed rescue program exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: typed rescue clauses catch only their types"
