#!/usr/bin/env bash
# Proc#call admits each argument by its source type. An enum argument travels
# on its integer carrier, and the admission compared the carrier, so calling a
# `Proc(E, ...)` with an enum value failed ("no overload matches
# 'Proc(E, NoReturn)#call' with type Int32"; stdlib Crystal::System::Signal
# calls its `::Signal ->` handlers this way) while an Int32 proc wrongly
# accepted an enum. Original Crystal admits the first and rejects the second.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-call-enum-argument.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# The proc box is still heap-allocated, so no-prelude fixtures link libgc.
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

enum E
  A = 5
  B = -7
end

lib LibE
  fun abs(x : E) : Int32
end
'

write_case() {
  printf '%s\n%s\n' "$PRELUDE" "$2" > "$WORK_DIR/$1.cr"
}

write_case enum_literal_argument '
f = ->(e : E) { LibC.exit(LibE.abs(e)) }
f.call(E::A)'

write_case enum_local_argument '
f = ->(e : E) { LibC.exit(LibE.abs(e)) }
x = E::B
f.call(x)'

write_case enum_to_int_proc '
f = ->(e : Int32) { LibC.exit(e) }
f.call(E::A)'

POSITIVE_CASES=(enum_literal_argument:5 enum_local_argument:7)
NEGATIVE_CASES=("enum_to_int_proc:no overload matches 'Proc(Int32, NoReturn)#call' with type E")

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
  printf '%d Proc#call enum-argument case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Proc#call enum-argument cases passed\n'
