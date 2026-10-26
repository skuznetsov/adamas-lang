#!/usr/bin/env bash
# A call through `io : Io` replays the inherited `Io#gets`, which forwards a
# `peek` narrowed by `if ascii && (peek = self.peek)` to the private untyped
# `gets_peek(d, limit, chomp, peek)`. The replay lowered that target under its
# shared `$arity4` name, without the call's argument types, so `peek` took the
# declaration-level `Sl?` (gets_peek itself reassigns `peek = self.peek`) and
# the orphan body was rejected with "undefined method 'index' for Nil". This
# is the IO#gets / IO#gets_peek shape of io.cr. The replay now specializes for
# the recorded argument types. A method Sl lacks stays rejected. Positive cases
# exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/virtual-replay-arity.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" gets_peek_body="$2" main="$3"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Sl
  def initialize(@n : Int32)
  end

  def index(x : Int32) : Int32?
    @n == x ? 1 : nil
  end
end

abstract class Io
  def peek : Sl?
    nil
  end

  def gets(d : Int32, limit : Int32, chomp = false) : Int32?
    ascii = d < 128
    if ascii && (peek = self.peek)
      gets_peek(d, limit, chomp, peek)
    else
      0
    end
  end

  private def gets_peek(d, limit, chomp, peek)
$gets_peek_body
  end
end

class Mem < Io
  def peek : Sl?
    Sl.new(7)
  end
end

class Buf < Io
  def peek : Sl?
    Sl.new(7)
  end
end

def run(io : Io)
  io.gets(7, 20) || 0
end

$main
CR
}

REASSIGN='    r = peek.index(d)
    return r &+ limit if r
    peek = self.peek
    peek ? 1 : 0'
NO_REASSIGN='    r = peek.index(d)
    return r &+ limit if r
    0'

write_case virtual_two_subclasses "$REASSIGN" 'LibC.exit(run(Mem.new) &+ run(Buf.new))'
write_case virtual_repeated_call "$REASSIGN" 'a = run(Mem.new)
LibC.exit(run(Mem.new) &+ a)'
# Control: without the reassignment the declaration-level type has no Nil.
write_case no_reassign_control "$NO_REASSIGN" 'LibC.exit(run(Mem.new) &+ run(Buf.new))'
# Control: a direct call on a concrete receiver needs no replay.
write_case direct_call_control "$REASSIGN" 'a = Mem.new.gets(7, 20) || 0
b = Buf.new.gets(7, 20) || 0
LibC.exit(a &+ b)'
# Negative: Sl declares no missing method.
write_case missing_method_rejected "${REASSIGN//peek.index(d)/peek.missing(d)}" 'LibC.exit(run(Mem.new) &+ run(Buf.new))'

POSITIVE=(virtual_two_subclasses virtual_repeated_call no_reassign_control direct_call_control)
NEGATIVE=(missing_method_rejected)

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
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "0" ]]; then
    printf 'FAIL %s (accepted)\n' "$name"
    failures=$((failures + 1))
  else
    printf 'PASS %s (rejected)\n' "$name"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
