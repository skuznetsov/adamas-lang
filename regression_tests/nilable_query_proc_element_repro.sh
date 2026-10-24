#!/usr/bin/env bash
# An unannotated query such as `Deque(T)#[]?` is registered as returning
# `Nil | T`. The union was spelled from the descriptor display name, so a Proc
# element became bare `Nil | Proc` and calling the narrowed value failed
# ("cannot call Proc#call without a concrete Proc signature"); stdlib
# Crystal::System::Signal hits this through `@@handlers[signal]?`. The element
# keeps its signature, so a mismatched call is still rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nilable-query-proc-element.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Proc boxes are heap-allocated, so no-prelude fixtures link libgc.
PRELUDE='@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end

struct Int32
  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end

class Deque(T)
  @v : T

  def initialize(@v : T)
  end

  def []?(i)
    i == 0 ? @v : nil
  end
end
'

write_case() {
  printf '%s\n%s\n' "$PRELUDE" "$2" > "$WORK_DIR/$1.cr"
}

write_case proc_element_query '
d = Deque(Proc(Int32, Int32)).new(->(x : Int32) { x })
h = d[0]?
LibC.exit(h ? h.call(9) : 1)'

write_case proc_element_query_miss '
d = Deque(Proc(Int32, Int32)).new(->(x : Int32) { x })
h = d[1]?
LibC.exit(h ? h.call(9) : 4)'

write_case proc_element_wrong_argument '
d = Deque(Proc(Int32, Int32)).new(->(x : Int32) { x })
h = d[0]?
h.call(1_i64) if h'

POSITIVE_CASES=(proc_element_query:9 proc_element_query_miss:4)
NEGATIVE_CASES=("proc_element_wrong_argument:no overload matches 'Proc(Int32, Int32)#call' with type Int64")

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${POSITIVE_CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
  for entry in "${NEGATIVE_CASES[@]}"; do
    name="${entry%%:*}"
    diagnostic="${entry#*:}"
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1 ||
        ! grep -qF "$diagnostic" "$WORK_DIR/$name.orig.log"; then
      printf 'ORACLE FAIL: original does not reject %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${POSITIVE_CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL positive %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS positive %s\n' "$name"
  else
    printf 'FAIL positive %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

for entry in "${NEGATIVE_CASES[@]}"; do
  name="${entry%%:*}"
  diagnostic="${entry#*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "1" ]] && grep -qF "$diagnostic" "$log" &&
      [[ ! -e "$WORK_DIR/$name.adamas" ]]; then
    printf 'PASS negative %s\n' "$name"
  else
    printf 'FAIL negative %s (exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d nilable query Proc-element case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'nilable query Proc-element cases passed\n'
