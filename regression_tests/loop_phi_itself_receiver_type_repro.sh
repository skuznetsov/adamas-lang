#!/usr/bin/env bash
# `value = elem.itself` inside a block/loop was inferred as Object, so
# `value <=> max` and Enumerable#max/min on Strings dispatched wrongly.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loop_phi_itself_receiver_type_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
check() {
  local case_name="$1" expected="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDERR ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/c1.cr" <<'CR'
def cor(value, memo)
  value <=> memo || raise "x"
end
def q1(xs : Array(String))
  max = uninitialized String
  xs.each_with_index do |elem, i|
    value = elem.itself
    STDERR.puts "q1 i=#{i} v=#{value} #{typeof(value)} max=#{i == 0 ? "-" : max}"
    if i == 0 || cor(value, max) > 0
      max = value
    end
  end
  max
end
def q2(xs : Array(String))
  max = ""
  xs.each do |elem|
    value = elem.itself
    max = value if (value <=> max) > 0
  end
  max
end
def q3(a : String, b : String)
  value = b.itself
  STDERR.puts cor(value, a)
  STDERR.puts cor(b, a)
end
STDERR.puts q1(["a", "d", "b"])
STDERR.puts q2(["a", "d", "b"])
q3("a", "d")
CR
check c1 'q1 i=0 v=a String max=-
q1 i=1 v=d String max=a
q1 i=2 v=b String max=d
d
d
1
1'

cat >"$WORK_DIR/c2.cr" <<'CR'
c = "d"
a = "a"
STDERR.puts({a, c}.max)
STDERR.puts({a, c}.min)
STDERR.puts([a, c].max)
STDERR.puts([a, c].min)
STDERR.puts({c, a}.max)
STDERR.puts([c, a].min)
STDERR.puts({3, 9, 1}.max)
STDERR.puts([3, 9, 1].min)
STDERR.puts({'x', 'b'}.min)
STDERR.puts([a, c].max?)
CR
check c2 'd
a
d
a
d
a
9
1
b
d'

if [ "$status" -ne 0 ]; then
  echo "FAIL: itself/max/min inferred the wrong receiver type" >&2
  exit 1
fi
echo "PASS: itself receiver type and max/min are correct"
