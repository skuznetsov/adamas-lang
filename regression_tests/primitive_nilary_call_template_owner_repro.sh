#!/usr/bin/env bash
# Regression: a nilary call on a concrete integer receiver runs the shared
# Int template body with self bound to that receiver type.
#
# Inside `Int32#odd?` the bare call `even?` looked up `Int32#even?`, found
# the template entry `Int#even?`, and kept that name: calls with arguments
# are remangled under the concrete base (`Int32#divisible_by?$Int32`), but a
# nilary call was not. Its body was lowered with self and `{{@type}}` bound
# to `Int`, so `x.odd?` failed to compile with `undefined constant Int::MIN`
# (Int#remainder expands `{{@type}}::MIN`). Explicit receivers with parens
# (`x.even?()`, `self.m()`) took the same path. Member access (`x.even?`)
# already re-owned the template key onto the receiver.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/primitive-nilary-owner.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
struct Int
  def pb_min_name
    {% begin %}{{@type}}::MIN{% end %}
  end

  def pb_via_bare
    pb_min_name
  end

  def pb_via_self
    self.pb_min_name()
  end
end

x = ARGV.size + 7
STDERR.puts x.odd?
STDERR.puts x.even?()
STDERR.puts x.odd?()
STDERR.puts x.pb_via_bare
STDERR.puts x.pb_via_self
y = x.to_i64 + 1
STDERR.puts y.odd?
STDERR.puts y.pb_via_bare
z = x.to_u8
STDERR.puts z.odd?
STDERR.puts z.pb_via_bare
CR

expected='true
false
true
-2147483648
-2147483648
false
-9223372036854775808
true
0'

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

echo "PASS: nilary integer calls keep the receiver as template self"
