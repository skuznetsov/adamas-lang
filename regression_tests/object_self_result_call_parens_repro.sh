#!/usr/bin/env bash
# Regression: a parenthesized call of an Object self-result wrapper
# (`5.me()`, `nil.itself()`) on a value receiver returns the receiver's type.
#
# Member access re-owned such a wrapper onto the concrete value receiver, but
# lower_call kept the shared Object body, whose `self` is Object: `5.me().tag`
# dispatched Object#tag and `typeof(5.me())` was Void. lower_call now re-owns
# the wrapper the same way. Its eager materialization also exposed that the
# re-own admission required a fresh replay binding, which a materialized
# target no longer has: a later `6.me.tag` or `nil.itself.nil?` fell back to
# the Object body. An admitted target now stays re-owned once materialized.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/object-self-result-call.XXXXXX")"

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

x = nil
STDERR.puts x.me().tag
STDERR.puts x.itself().tag
STDERR.puts 5.me().tag
STDERR.puts 6.me.tag
STDERR.puts Foo.new.me().tag
STDERR.puts Foo.new.me.tag
STDERR.puts Bar.new.me().tag
STDERR.puts nil.itself().nil?
STDERR.puts x.itself.nil?
STDERR.puts nil.itself.nil?
STDERR.puts typeof(5.me())
STDERR.puts typeof(x.me())
a = [1, nil, 3] of Int32?
STDERR.puts a.map { |v| v.itself().tag }.inspect
STDERR.puts a.map { |v| v.me().tag }.inspect
CR

expected='7
7
8
8
9
9
10
true
true
true
Int32
Nil
[8, 7, 8]
[8, 7, 8]'

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
  echo "FAIL: object self-result call program did not compile" >&2
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
echo "PASS object_self_result_call_parens"
