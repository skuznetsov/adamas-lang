#!/usr/bin/env bash
# An untyped module class method is registered under a shared arity key
# (`M.process$arity1`); its call lowers the callsite specialization
# (`M.process$Int32`). The tracked-signature safety net resolved the recorded
# callsite back to the bare arity key, which carries no parameter types, and
# lowered the body again with the parameter typed Void. A body passing that
# parameter to Proc#call was then rejected ("no overload matches
# 'Proc(Int32, Void)#call' with type Void"); prelude hello hits this through
# Crystal::System::Signal.process(signal). A genuinely mismatched argument
# must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/untyped-module-method-arity-safety-net.XXXXXX")"
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

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int64
  @[Primitive(:convert)]
  def to_i32! : Int32
  end
end

struct UInt64
  @[Primitive(:convert)]
  def to_i32! : Int32
  end
end

struct Int32
  @[Primitive(:binary)]
  def &+(other : Int32) : self
  end
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end

module M
  @@h : (Int32 ->)? = nil
  @@r = 0

  def self.r
    @@r
  end

  def self.set(h : Int32 ->)
    @@h = h
  end

  def self.hit(s : Int32)
    @@r = @@r &+ s
  end

  def self.process(signal) : Nil
    if handler = @@h
      handler.call(signal)
    end
  end

  def self.process_wide(signal) : Nil
    if handler = @@h
      handler.call(signal.to_i32!)
    end
  end
end

M.set(->(s : Int32) { M.hit(s); nil })'

write_case() {
  printf '%s\n%s\n' "$PRELUDE" "$2" > "$WORK_DIR/$1.cr"
}

write_case untyped_param_to_proc_call '
M.process(5)
LibC.exit(M.r)'

write_case untyped_param_two_callsites '
M.process_wide(2_u64)
M.process_wide(3_i64)
M.process(4)
LibC.exit(M.r)'

write_case mismatched_argument '
M.process(5)
M.process(2_i64)
LibC.exit(M.r)'

POSITIVE_CASES=(untyped_param_to_proc_call:5 untyped_param_two_callsites:9)
NEGATIVE_CASE=mismatched_argument
ORACLE_DIAGNOSTIC="#call' with type Int64"
NEGATIVE_DIAGNOSTIC="#call' with type Int64"

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
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
      "$WORK_DIR/$NEGATIVE_CASE.cr" -o "$WORK_DIR/$NEGATIVE_CASE.orig" > "$WORK_DIR/$NEGATIVE_CASE.orig.log" 2>&1 ||
      ! grep -qF "$ORACLE_DIAGNOSTIC" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
    printf 'ORACLE FAIL: original does not reject %s\n' "$NEGATIVE_CASE" >&2
    cat "$WORK_DIR/$NEGATIVE_CASE.orig.log" >&2
    exit 2
  fi
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

log="$WORK_DIR/$NEGATIVE_CASE.adamas.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$NEGATIVE_CASE.cr" \
  -o "$WORK_DIR/$NEGATIVE_CASE.adamas" > "$log" 2>&1 || true
if [[ "$(exit_code_of "$log")" == "1" ]] && grep -qF "$NEGATIVE_DIAGNOSTIC" "$log" &&
    [[ ! -e "$WORK_DIR/$NEGATIVE_CASE.adamas" ]]; then
  printf 'PASS negative %s\n' "$NEGATIVE_CASE"
else
  printf 'FAIL negative %s (exit %s): %s\n' "$NEGATIVE_CASE" "$(exit_code_of "$log")" \
    "$(grep -m1 -i 'error' "$log" || tail -1 "$log")"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d untyped module-method safety-net case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'untyped module-method safety-net cases passed\n'
