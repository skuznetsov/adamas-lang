#!/usr/bin/env bash
# A local captured by a block proc is read through its box or closure cell.
# A truthy condition lends a one-read proof to the captured name, but only a
# bare `if source` registered it: in `if source && span` the identifier reads of
# the `&&` chain were never collected, so the then-body re-read the box as
# `Nil | String`. Stage 2 failed in diagnostic_formatter.cr with "no overload
# matches DiagnosticFormatter.extract_lines for argument types
# (Nil | String, Span)".
# Operands below an `||` do not dominate the then-body and must stay unnarrowed;
# a reassignment in the body must also drop the proof.
# Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure-and-narrow.XXXXXX")"

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
  def initialize(@n : Int32); end

  def n
    @n
  end
end

struct Sp
  def initialize(@l : Int32); end

  def l
    @l
  end
end

def take(s : Str, sp : Sp) : Int32
  s.n &+ sp.l
end

def run(&blk : Int32 -> Int32) : Int32
  blk.call(0)
end

# `flag ? src : nil` keeps `source` nilable in the original compiler too
# (a `Str?` restriction alone would be instantiated with the argument's `Str`).
def go(src : Str, sp : Sp, flag : Bool) : Int32
  source = flag ? src : nil
  other = flag ? nil : src
  run do |io|
    acc = io
HEAD
    printf '%s\n' "$body"
    cat <<'TAIL'
    acc
  end
end

LibC.exit(go(Str.new(40), Sp.new(2), true))
TAIL
  } > "$WORK_DIR/$name.cr"
}

write_case and_left "    if source && sp
      acc = take(source, sp)
    end"
write_case and_right "    if sp && source
      acc = take(source, sp)
    end"
write_case and_chain "    if sp && source && sp
      acc = take(source, sp)
    end"
write_case elsif_and "    if io > 5
      acc = 1
    elsif source && sp
      acc = take(source, sp)
    end"
# Negative: `||` proves neither operand.
write_case or_rejected "    if source || sp
      acc = take(source, sp)
    end"
# Negative: an operand below `||` does not dominate the then-body.
write_case or_below_and_rejected "    if (other || source) && sp
      acc = take(source, sp)
    end"
# Negative: a reassignment in the body drops the proof.
write_case reassigned_rejected "    if source && sp
      source = flag ? nil : src
      acc = take(source, sp)
    end"

POSITIVE=(and_left and_right and_chain elsif_and)
NEGATIVE=(or_rejected or_below_and_rejected reassigned_rejected)

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
  printf '%d closure capture && narrowing case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Closure capture && narrowing cases passed\n'
