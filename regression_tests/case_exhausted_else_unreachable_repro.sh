#!/usr/bin/env bash
# A `when` type check that matches every value the case subject can hold
# makes the later branches and the else body unreachable. Crystal types the
# subject there as NoReturn and never instantiates their calls. V2 lowered
# the else body anyway, so Enumerable#flat_map's `else ary.push(v)` with
# `v : Array(Diagnostic)` failed stage 2 with "no overload matches
# Array(Diagnostic)#push for argument types (Array(Diagnostic))".
# The else body must still be lowered, and rejected, when a subject type
# can reach it. Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/case-exhausted-else.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" signature="$2" branches="$3" call="$4"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Sink
  def push(x : Int32) : Int32
    x
  end
end

class B
end

class C
end

# A declared ivar type keeps the value a union; a plain argument would
# instantiate g for its concrete type only.
class Box
  @x : Int32 | B | C

  def initialize(@x : Int32 | B | C)
  end

  def x
    @x
  end
end

class Box2
  @x : Int32 | B

  def initialize(@x : Int32 | B)
  end

  def x
    @x
  end
end

def g($signature)
  case x
$branches
  end
end

LibC.exit($call)
CR
}

# Non-union subject: `when B` always matches, else is dead.
write_case single_type "x" "  when B
    42
  else
    Sink.new.push(x)" "g(B.new)"
# Union subject: Int32, then B and C cover every arm.
write_case union_covered "x" "  when Int32
    1
  when B, C
    42
  else
    Sink.new.push(x)" "g(Box.new(B.new).x)"
# Later `when` after an exhaustive one is dead as well.
write_case later_when_dead "x" "  when B
    42
  when C
    Sink.new.push(x)
  else
    Sink.new.push(x)" "g(B.new)"
# Control: C reaches the else body, which must still run.
write_case else_reachable "x" "  when Int32
    1
  when B
    2
  else
    42" "g(Box.new(C.new).x)"
# Negative: B reaches the else body, so push(B) must be rejected.
write_case else_live_rejected "x" "  when Int32
    42
  else
    Sink.new.push(x)" "g(Box2.new(1).x)"

POSITIVE=(single_type union_covered later_when_dead else_reachable)
NEGATIVE=(else_live_rejected)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
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
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected 42\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]] && grep -q "no overload matches" "$log"; then
    printf 'PASS %s (rejected)\n' "$name"
  else
    printf 'FAIL %s: expected a no overload matches error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d exhausted case else case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Exhausted case else cases passed\n'
