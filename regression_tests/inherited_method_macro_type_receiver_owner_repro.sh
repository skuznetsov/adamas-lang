#!/usr/bin/env bash
# Regression: an inherited method whose body expands `@type` is lowered per
# receiver type, as Crystal instantiates it.
#
# A body declared in an ancestor (`abstract struct Nb`, `abstract class Cb`,
# or a concrete parent `P`) that expands `{{@type}}::K` or `@type.name` must
# see the receiver class as `@type`. The receiver-owner rule only kept the
# receiver owner for reference receivers whose self dispatch differed, so
# struct receivers, and member-access calls whose return type was read from
# the ancestor key, lowered the body with the ancestor as self: `N1.new.entry_k`
# failed with `undefined constant Nb::K`, and `Q.new.k` read `P::K`. Shared
# bodies that self-call such a method (`via_bare`, `self.entry_k()`) differ
# the same way. Reference#inspect expands `@type.instance_vars` and now
# specializes per receiver as well.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited-macro-type-owner.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
abstract struct Nb
  def entry_k
    {% begin %}{{@type}}::K{% end %}
  end

  def entry_k_plus
    {% begin %}{{@type}}::K + 0{% end %}
  end

  def via_bare
    entry_k
  end

  def via_self
    self.entry_k() + 10
  end

  def type_name
    {{@type.name.stringify}}
  end
end

struct N1 < Nb
  K = 2
end

struct N2 < Nb
  K = 5
end

abstract class Cb
  def entry_k
    {% begin %}{{@type}}::K{% end %}
  end

  def via_bare
    entry_k * 100
  end
end

class C1 < Cb
  K = 3
end

class C2 < Cb
  K = 4
end

class P
  K = 1

  def k
    {% begin %}{{@type}}::K{% end %}
  end
end

class Q < P
  K = 7
end

record Pt, x : Int32, y : Int32

class Plain
  def initialize(@a : Int32)
  end
end

n = N1.new
STDERR.puts n.entry_k
STDERR.puts N2.new.entry_k_plus
STDERR.puts n.via_bare
STDERR.puts N2.new.via_self
STDERR.puts n.entry_k()
STDERR.puts N2.new.type_name
v = n.entry_k_plus
STDERR.puts v
c = C1.new
STDERR.puts c.entry_k
STDERR.puts C2.new.entry_k
STDERR.puts c.via_bare
STDERR.puts C2.new.entry_k()
STDERR.puts "i=#{C1.new.entry_k}/#{N2.new.entry_k}"
STDERR.puts [C2.new.entry_k, N1.new.entry_k].sum
w = C1.new.entry_k
STDERR.puts w
maybe = ARGV.size > 5 ? nil : C2.new
STDERR.puts maybe.try(&.entry_k)
STDERR.puts P.new.k
STDERR.puts Q.new.k
q = Q.new
STDERR.puts q.k + P.new.k
p1 = Pt.new(1, 2)
STDERR.puts p1 == Pt.new(1, 2)
STDERR.puts p1.inspect
STDERR.puts p1.to_s
STDERR.puts Plain.new(7).inspect.includes?("Plain")
CR

expected='2
5
2
15
2
N2
2
3
4
300
4
i=3/5
6
3
4
1
7
8
true
Pt(@x=1, @y=2)
Pt(@x=1, @y=2)
true'

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

echo "PASS: inherited @type bodies are lowered per receiver"
