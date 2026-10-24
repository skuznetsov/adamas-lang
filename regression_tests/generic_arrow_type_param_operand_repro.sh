#!/usr/bin/env bash
# A type parameter bound to arrow notation (`Box(Int32 ->)`) was spliced into
# declared types as text, so `V?` became the proc `Int32 -> ?` and `V | Nil`
# for `Int32 -> Int32` a proc returning `Int32 | Nil`; the narrowed value then
# failed Proc#call ("expects Int32 -> ?"). The bound arrow stays one operand.
# A proc whose input does not match the parameter must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-arrow-type-param-operand.XXXXXX")"
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

class Box(V)
  def initialize(@v : V?)
  end

  def get? : V?
    @v
  end

  def get_u : V | Nil
    @v
  end
end

def run(b, hit) : Int32
  if f = b.get?
    f.call(5)
    hit
  else
    1
  end
end
'

write_case() {
  printf '%s\n%s\n' "$PRELUDE" "$2" > "$WORK_DIR/$1.cr"
}

write_case nilable_arrow_param '
LibC.exit(run(Box(Int32 ->).new(->(x : Int32) { nil }), 5))'

write_case nilable_alias_arrow_param '
alias H = Int32 ->
LibC.exit(run(Box(H).new(->(x : Int32) { nil }), 6))'

write_case nilable_alias_arrow_result '
alias H = Int32 -> Int32
LibC.exit(run(Box(H).new(->(x : Int32) { x }), 7))'

write_case union_nil_arrow_param '
b = Box(Int32 ->).new(->(x : Int32) { nil })
if f = b.get_u
  f.call(5)
  LibC.exit(3)
end
LibC.exit(1)'

write_case nil_arrow_value '
LibC.exit(run(Box(Int32 -> Int32).new(nil), 5))'

write_case arrow_input_mismatch '
Box(Int32 ->).new(->(x : Int64) { nil })'

POSITIVE_CASES=(nilable_arrow_param:5 nilable_alias_arrow_param:6 nilable_alias_arrow_result:7 union_nil_arrow_param:3 nil_arrow_value:1)
NEGATIVE_CASES=("arrow_input_mismatch:Proc(Int64, Nil)")

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
  printf '%d generic arrow type-parameter case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'generic arrow type-parameter cases passed\n'
