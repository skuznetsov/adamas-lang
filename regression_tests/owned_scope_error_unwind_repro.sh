#!/usr/bin/env bash
# Regression: lowering failures inside nested scopes must propagate unchanged.
#
# Scope owners (case arms, loop bodies, inline-yield bodies, closures) checked
# that their scope was still innermost from `ensure`. Helpers that push a
# scope without error cleanup (e.g. the String#each_char intrinsic) leave it on
# the stack when an exact-result suspension unwinds through them, so the
# owner's ensure check raised "... lost its owned Block scope" and replaced the
# suspension. The suspension's catcher never saw it and compilation failed for
# valid programs such as Symbol.needs_quotes? (a `return` inside
# each_char_with_index inside a case arm). Owners now close the nested scopes
# on the error path and re-raise the original exception; genuine diagnostics
# raised inside nested scopes must still reach the user.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/owned-scope-unwind.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/valid.cr" <<'CR'
STDERR.puts Symbol.needs_quotes?("abc")
STDERR.puts Symbol.needs_quotes?("a b")
STDERR.puts Symbol.needs_quotes?("1a")
STDERR.puts Symbol.needs_quotes?("+")
CR

cat > "$WORK_DIR/invalid.cr" <<'CR'
def each2
  yield 1
  yield 2
end

each2 do |i|
  case i
  when 1
    "abc".each_char do |c|
      i.no_such_method_here
    end
  end
end
CR

expected='false
true
true
false'
diagnostic="undefined method 'no_such_method_here' for Int32"

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/valid.cr" -o "$WORK_DIR/valid_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/valid_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
  if "$CRYSTAL_BIN" build "$WORK_DIR/invalid.cr" -o "$WORK_DIR/invalid_oracle" > "$WORK_DIR/oracle_invalid.log" 2>&1 ||
     ! grep -qF "$diagnostic" "$WORK_DIR/oracle_invalid.log"; then
    echo "ORACLE_MISMATCH: invalid program diagnostic" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/valid.cr" -o "$WORK_DIR/valid" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/valid" ]]; then
  echo "FAIL: valid program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/valid" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: valid program exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

if "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/invalid.cr" -o "$WORK_DIR/invalid" > "$WORK_DIR/build_invalid.log" 2>&1; then
  echo "FAIL: invalid program compiled" >&2
  exit 1
fi
if ! grep -qF "$diagnostic" "$WORK_DIR/build_invalid.log" || grep -q 'lost its owned' "$WORK_DIR/build_invalid.log"; then
  echo "FAIL: invalid program lost its source diagnostic" >&2
  strip < "$WORK_DIR/build_invalid.log" | grep -i error | head -5 >&2
  exit 1
fi

echo "PASS: nested-scope lowering failures propagate unchanged"
