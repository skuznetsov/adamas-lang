#!/usr/bin/env bash
# A statement that starts with a brace literal is an ordinary operand: after
# its postfix chain (`{a, b}.m(x)`), infix operators, ternaries and the rest of
# the expression must still be parsed. The statement fast path for `{` returned
# right after the postfix chain, so `if {1, 2}.includes?(x) && rt.is_a?(T)`
# lost `&& rt.is_a?(T)`: the right operand became the first statement of the
# then-body and the is_a? narrowing disappeared. Stage2 failed in
# TypeInferenceEngine#infer_receiverless_method_call with "no overload matches
# enum_constructor_arguments_match? for argument types (Type, Array(Type))".
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brace-statement-infix.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Tuple
  def has_any? : Bool
    true
  end

  def has_none? : Bool
    false
  end

  def two : Int32
    2
  end
end

class Foo
  def k : Int32
    40
  end
end

class Counter
  def initialize
    @n = 0
  end

  def n : Int32
    @n
  end

  def bump : Bool
    @n = @n &+ 1
    true
  end
end

def no : Bool
  false
end

def yes : Bool
  true
end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

# name:expected-exit
CASES=()

add_case() {
  CASES+=("$1:$2")
  write_case "$1" "$3"
}

add_case and_condition_keeps_right_operand 20 '
def run : Int32
  if {1, 2}.has_any? && no
    10
  else
    20
  end
end
LibC.exit(run)'

add_case and_condition_keeps_is_a_narrowing 41 '
def run(x : Foo | Int32) : Int32
  if {1, 2}.has_any? && x.is_a?(Foo)
    x.k
  else
    1
  end
end
LibC.exit(run(Foo.new) &+ run(5))'

add_case or_condition_keeps_right_operand 3 '
def run : Int32
  if {1, 2}.has_none? || yes
    3
  else
    7
  end
end
LibC.exit(run)'

add_case statement_and_skips_right_operand 0 '
c = Counter.new
{1, 2}.has_none? && c.bump
LibC.exit(c.n)'

add_case statement_ternary_is_the_value 5 '
def run : Int32
  {1, 2}.has_none? ? 4 : 5
end
LibC.exit(run)'

add_case statement_arithmetic_is_the_value 5 '
def run : Int32
  {1, 2}.two &+ 3
end
LibC.exit(run)'

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}" want="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$want" ]]; then
      printf 'ORACLE FAIL: original %s exited %s, not %s\n' "$name" \
        "$(exit_code_of "$WORK_DIR/$name.orig.run")" "$want" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}" want="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -v '^\[RUN_SAFE' "$log" | grep -m3 -i 'error\|overload' >&2 || tail -5 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  got="$(exit_code_of "$run_log")"
  if [[ "$got" == "$want" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: exit %s, expected %s\n' "$name" "$got" "$want" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d brace statement case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all brace statement cases passed\n'
