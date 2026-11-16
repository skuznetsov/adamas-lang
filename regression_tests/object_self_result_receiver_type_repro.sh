#!/usr/bin/env bash
# Regression: an Object wrapper whose body is `self` (`itself`, `not_nil!`)
# returns the receiver's own type, as every Crystal instantiation types
# `self` as the receiver.
#
# V2 shares one Object-owned body across value receivers, so its result was
# typed Object. `nil.itself.nil?` printed false, and `x.me.tag` on Nil, Int32
# or a struct dispatched Object#tag. On a union receiver the inline union
# dispatcher typed every arm with that Object estimate: `Array(Int32?)#compact`
# (`compact_map &.itself`) folded its `is_a?(Nil)` check to false and kept
# nil elements, and `(Nil | Baz)#me`, where Baz declares its own `me`, read
# the Nil arm as zero. The member-access path now infers the re-owned
# receiver body with `self` as the receiver. The union dispatcher types each
# arm that inherits the self-result wrapper by the arm itself, and gives an
# arm with its own declaration its own result.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/object-self-result.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class Object
  def me
    self
  end

  def tag : Int32
    2
  end
end

struct Nil
  def tag : Int32
    7
  end
end

struct Int32
  def tag : Int32
    8
  end
end

struct Foo
  def tag : Int32
    9
  end
end

class Bar
  def tag : Int32
    10
  end
end

struct Baz
  def me
    5
  end
end

x = nil
STDERR.puts x.me.tag
STDERR.puts x.itself.tag
STDERR.puts 5.me.tag
STDERR.puts Foo.new.me.tag
STDERR.puts Bar.new.me.tag
STDERR.puts nil.itself.nil?
a = [1, nil, 3] of Int32?
STDERR.puts a.compact.size
STDERR.puts a.compact_map(&.itself).size
STDERR.puts a.map(&.itself).inspect
STDERR.puts a.map { |v| v.itself.tag }.inspect
STDERR.puts a.map { |v| v.me.tag }.inspect
u = a[1]
STDERR.puts u.itself.nil?
STDERR.puts typeof(u.itself) == typeof(u)
STDERR.puts typeof(x.me)
STDERR.puts typeof(5.me)
w = [Baz.new, nil].first
STDERR.puts w.me.inspect
v = [nil, Baz.new].first
STDERR.puts v.me.inspect
CR

expected='7
7
8
9
10
true
2
2
[1, nil, 3]
[8, 7, 8]
[8, 7, 8]
true
true
Nil
Int32
5
nil'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: object self-result program did not compile" >&2
  strip < "$WORK_DIR/build.log" | tail -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi
echo "PASS object_self_result_receiver_type"
