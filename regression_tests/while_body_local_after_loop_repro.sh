#!/usr/bin/env bash
# A local first assigned in a `while` body outlives the loop. lower_while
# built header phis only for locals that already had a pre-loop value, so
# such a local vanished with the loop scope: Stage 2 stopped with "undefined
# method 'new_year_is_dst'" in Time::TZ (time/tz.cr), which reads
# `new_year_is_dst`, `datetime1` and `datetime2` after `while true ... break`.
# After `while true` with every break past the assignment the local keeps its
# narrow type (`unix_seconds < datetime2` needs Int64, not Int64?).
# A local first assigned inside a block body stays block-local (reject case).
# Each accept case exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/while-body-local.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

CASES=(while_true_break_flag while_true_break_narrow toplevel_while_true conditional_loop_break
  branch_local_in_method normal_exit_last_value zero_iterations_nil break_before_assignment nested_loops)
REJECT_CASES=(block_local_stays_local)

cat > "$WORK_DIR/while_true_break_flag.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(n : Int32) : Int32
  i = n
  while true
    flag = i > 2
    break if flag
    i &+= 1
  end
  flag ? 42 : 1
end
LibC.exit(f(0))
CR

cat > "$WORK_DIR/while_true_break_narrow.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(n : Int32) : Int32
  i = n
  while true
    d = i &* 10
    break if d > 25
    i &+= 1
  end
  d &+ 12
end
LibC.exit(f(0))
CR

cat > "$WORK_DIR/toplevel_while_true.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
i = 0
while true
  flag = i > 2
  break if flag
  i &+= 1
end
LibC.exit(flag ? 42 : 1)
CR

cat > "$WORK_DIR/conditional_loop_break.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(n : Int32) : Int32
  i = n
  while i < 10
    flag = i > 2
    break if flag
    i &+= 1
  end
  flag ? 42 : 1
end
LibC.exit(f(0))
CR

cat > "$WORK_DIR/branch_local_in_method.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Z
  def g(n : Int32) : Int32
    if n == 7
      r = 0
    else
      i = n
      while true
        flag = i > 2
        break if flag
        i &+= 1
      end
    end
    if flag
      42
    else
      1
    end
  end
end
LibC.exit(Z.new.g(0))
CR

cat > "$WORK_DIR/normal_exit_last_value.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(n : Int32) : Int32
  i = n
  while i < 3
    last = i
    i &+= 1
  end
  last ? last &+ 40 : 1
end
LibC.exit(f(0))
CR

cat > "$WORK_DIR/zero_iterations_nil.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(n : Int32) : Int32
  i = n
  while i < 3
    last = i
    i &+= 1
  end
  last ? 1 : 42
end
LibC.exit(f(9))
CR

cat > "$WORK_DIR/break_before_assignment.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(n : Int32) : Int32
  i = n
  while true
    break if i == 3
    v = i &* 10
    i &+= 1
  end
  v ? v &+ 22 : 1
end
LibC.exit(f(0))
CR

cat > "$WORK_DIR/nested_loops.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def f(n : Int32) : Int32
  total = 0
  j = 0
  while j < 2
    i = n
    while true
      d = i &* 7
      break if d > 10
      i &+= 1
    end
    total &+= d
    j &+= 1
  end
  total &+ 14
end
LibC.exit(f(0))
CR

cat > "$WORK_DIR/block_local_stays_local.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def run(&)
  yield
end
def f(n : Int32) : Int32
  i = n
  while i < 3
    run { t = 5 }
    i &+= 1
  end
  t
end
LibC.exit(f(0))
CR

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${CASES[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
  for name in "${REJECT_CASES[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -a '^error' "$log" >&2 || tail -3 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  got="$(exit_code_of "$run_log")"
  if [[ "$got" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: exit %s, expected 42\n' "$name" "$got" >&2
    failures=$((failures + 1))
  fi
done

for name in "${REJECT_CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "0" ]]; then
    printf 'FAIL %s: accepted, original Crystal rejects it\n' "$name" >&2
    failures=$((failures + 1))
  else
    printf 'PASS %s (rejected)\n' "$name"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d while body-local case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all while body-local cases passed\n'
