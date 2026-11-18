#!/usr/bin/env bash
# Regression: an ensure body runs when an exception leaves its begin.
#
# Ensure was emitted only on normal completion and early exits. An exception
# from an ensure-only begin, an exception no rescue clause matched, and an
# exception raised by a rescue clause all skipped it. The begin now pushes
# its own ensure frame around the body and rescue clauses; the landing runs
# the ensure body and re-raises the same exception. As in Crystal, the else
# body runs outside that frame, so an exception from else skips ensure.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ensure-on-raise.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
def ensure_only
  begin
    raise "x"
  ensure
    STDERR.puts "e1"
  end
end

def unmatched
  begin
    raise KeyError.new("k")
  rescue e : ArgumentError
    STDERR.puts "no"
  ensure
    STDERR.puts "e2"
  end
end

def raise_in_rescue
  begin
    raise "y"
  rescue
    raise "z"
  ensure
    STDERR.puts "e3"
  end
end

def else_raise
  begin
    STDERR.puts "body"
  rescue
    STDERR.puts "wrong"
  else
    raise "from else"
  ensure
    STDERR.puts "skipped"
  end
end

def nested
  begin
    begin
      raise "inner"
    ensure
      STDERR.puts "e-in"
    end
  ensure
    STDERR.puts "e-out"
  end
end

def ensure_raises
  begin
    raise "first"
  ensure
    STDERR.puts "e-r"
    raise "second"
  end
end

def ensure_rescues
  begin
    raise "orig"
  ensure
    begin
      raise "inside"
    rescue e
      STDERR.puts "ens caught #{e.message}"
    end
  end
end

def with_cleanup
  begin
    yield
  ensure
    STDERR.puts "cleanup"
  end
end

def method_level(k : Int32) : Int32
  raise "ml" if k == 0
  k
ensure
  STDERR.puts "e-ml #{k}"
end

def early : Int32
  begin
    return 4
  ensure
    STDERR.puts "e4"
  end
end

{% for m in %w(ensure_only unmatched raise_in_rescue else_raise nested ensure_raises ensure_rescues) %}
  begin
    {{m.id}}
  rescue e
    STDERR.puts "c #{e.message}"
  end
{% end %}
begin
  with_cleanup { raise "blk" }
rescue e
  STDERR.puts "c #{e.message}"
end
STDERR.puts method_level(7)
begin
  method_level(0)
rescue e
  STDERR.puts "c #{e.message}"
end
STDERR.puts early
begin
  raise "final"
rescue e
  STDERR.puts "c #{e.message}"
end
STDERR.puts "done"
CR

expected='e1
c x
e2
c k
e3
c z
body
c from else
e-in
e-out
c inner
e-r
c second
ens caught inside
c orig
cleanup
c blk
e-ml 7
7
e-ml 0
c ml
e4
4
c final
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
  echo "FAIL: ensure program did not compile" >&2
  strip < "$WORK_DIR/build.log" | tail -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: ensure program exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: ensure runs when an exception leaves its begin"
