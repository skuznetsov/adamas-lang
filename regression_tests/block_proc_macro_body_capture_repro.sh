#!/usr/bin/env bash
# Regression: a closure whose body is a macro control node captures the
# enclosing locals the expanded code names.
#
# Capture detection for block procs and proc literals scanned the closure
# AST for identifiers, but `{% for %}`, `{% if %}` and macro literal nodes
# keep their code as text until lowering expands it. A parameter used only
# inside such a body (Reference#inspect's `exec_recursive(:inspect) do
# {% for ivar in @type.instance_vars %} io << ...; @{{ivar.id}}.inspect io
# {% end %} end`) was not captured: the closure lowered `io` as an unresolved
# call, read a null pointer and crashed. Writes inside the expansion were
# missed the same way, so the enclosing scope kept a stale value.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block-proc-macro-capture.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class Foo
  def initialize(@a : Int32, @b : String)
  end

  def wrap(&block : -> Nil)
    block.call
  end

  def show(io : IO)
    wrap do
      {% for ivar in @type.instance_vars %}
        io << " @{{ivar.id}}="
        @{{ivar.id}}.inspect(io)
      {% end %}
      nil
    end
  end

  def count_ivars
    count = 0
    wrap do
      {% for ivar in @type.instance_vars %}
        count += 1
      {% end %}
      nil
    end
    count
  end

  def flagged(io : IO)
    wrap do
      {% if @type.instance_vars.size == 2 %}
        io << "two"
      {% else %}
        io << "other"
      {% end %}
      nil
    end
  end

  def proc_literal(io : IO)
    total = 0
    f = -> do
      {% for ivar in @type.instance_vars %}
        io << "<{{ivar.id}}>"
        total += 10
      {% end %}
      nil
    end
    f.call
    total
  end
end

foo = Foo.new(7, "x")
s = String.build { |io| foo.show(io) }
STDERR.puts s
STDERR.puts foo.count_ivars
STDERR.puts String.build { |io| foo.flagged(io) }
t = 0
STDERR.puts String.build { |io| t = foo.proc_literal(io) }
STDERR.puts t
CR

expected=' @a=7 @b="x"
2
two
<a><b>
20'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH\|run_safe\.sh: ' || true; }

run_program() {
  local bin="$1"
  set +e
  out="$("$SAFE_RUNNER" "$bin" 5 256 2>&1)"
  status=$?
  set -e
  printed="$(printf '%s\n' "$out" | strip)"
}

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  run_program "$WORK_DIR/m_oracle"
  if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: exit=$status" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

run_program "$WORK_DIR/m"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: closures capture locals named inside macro bodies"
