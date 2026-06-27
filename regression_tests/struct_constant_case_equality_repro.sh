#!/usr/bin/env bash
# Regression: case/when over a struct constant must use Crystal's
# `condition === subject` semantics, not raw storage/pointer equality.
# Pre-fix, `x == TypeRef::STRING` was true but
# `case x; when TypeRef::STRING` missed because case fallback emitted raw Eq.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/struct-constant-case.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$SRC" <<'CR'
struct TypeRef
  getter id : UInt32

  def initialize(@id : UInt32)
  end

  STRING = new(15_u32)

  def ==(other : TypeRef) : Bool
    @id == other.id
  end
end

x = TypeRef.new(15_u32)
puts "eq=#{x == TypeRef::STRING}"
case x
when TypeRef::STRING
  puts "case=hit"
else
  puts "case=miss"
end
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 2048 "$SRC" -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_status=$?
set -e
if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compile failed (status $compile_status)" >&2
  tail -100 "$COMPILE_LOG" >&2
  exit 2
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

stdout="$(awk '/^=== STDOUT ===/{flag=1;next}/^=== STDERR ===/{flag=0}flag' "$RUN_LOG" | tr -d '\r')"
expected=$'eq=true\ncase=hit'

if [[ $run_status -eq 0 && "$stdout" == "$expected" ]]; then
  echo "PASS: struct constant case uses value equality"
  exit 0
fi

echo "FAIL: struct constant case still misses" >&2
echo "run status: $run_status" >&2
echo "expected stdout:" >&2
printf '%s\n' "$expected" >&2
echo "actual stdout:" >&2
printf '%s\n' "$stdout" >&2
echo "--- run log tail ---" >&2
tail -100 "$RUN_LOG" >&2
exit 1
