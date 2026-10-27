#!/usr/bin/env bash
# A def specialized for a `Nil` argument (`run(nil)` against `st : Str?`)
# types `st` as `Nil`, so `st ? t.it(st) : nil` has a constant condition.
# `lower_if` lowered only the live branch, but `lower_ternary` lowered both,
# and the dead true branch demanded `Tk#it(Nil)`, which has no overload.
# Original Crystal never types that branch. Stage 2 stopped in
# infer_concrete_return_type_from_body with "no overload matches
# IdentityDryRunTracker#intern_type_name for argument types (Nil)".
# The ternary now prunes a constant condition the same way. The other cases
# keep both branches for a `Str?` argument, and keep the condition's and the
# live branch's local writes.
# Each case exits with its expected code under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/static-ternary.XXXXXX")"

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

class Str
  def initialize(@n : Int32)
  end

  def n : Int32
    @n
  end
end

class Tk
  def it(s : Str) : Int32
    s.n &* 10
  end
end

class L
  @tk : Tk? = Tk.new

  def wa(&)
    yield
  end

  def inner(s : Str?) : Int32
    s ? s.n : 0
  end
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

add_case nil_arg_dead_true_branch 31 '
class L
  def run(st : Str?) : Int32
    rv = st ? Tk.new.it(st) : nil
    rv || 1
  end
end
LibC.exit(L.new.run(Str.new(3)) &+ L.new.run(nil))'

add_case nil_arg_dead_branch_then_block 34 '
class L
  def run(st : Str? = nil) : Int32
    r = 0
    if tk = @tk
      rv = st ? tk.it(st) : nil
      r = rv || 1
    end
    x = wa do
      inner(st)
    end
    r &+ x
  end
end
LibC.exit(L.new.run(Str.new(3)) &+ L.new.run(nil))'

add_case union_arg_keeps_both_branches 31 '
class L
  def run(st : Str?) : Int32
    rv = st ? Tk.new.it(st) : nil
    rv || 1
  end

  def go : Int32
    s = Str.new(3).as(Str?)
    run(s) &+ run(nil.as(Str?))
  end
end
LibC.exit(L.new.go)'

add_case static_branch_keeps_local_writes 97 '
class L
  def run(st : Str?) : Int32
    k = 0
    x = 0
    v = (k = 40; st) ? (x = 5; st.n) : (x = 9; 0)
    k &+ x &+ v
  end
end
LibC.exit(L.new.run(Str.new(3)) &+ L.new.run(nil))'

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
  printf '%d static ternary case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all static ternary cases passed\n'
