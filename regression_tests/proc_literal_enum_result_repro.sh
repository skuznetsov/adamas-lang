#!/usr/bin/env bash
# A proc literal whose result is an enum value has that enum as its Proc
# result type. The enum value travels on its integer carrier and the literal
# published the carrier (`Proc(..., Int32)`), so stdlib
# Exception::CallStack.unwind failed on prelude hello with "argument #1 of
# 'LibUnwind.backtrace' must be Proc(..., LibUnwind::ReasonCode), not
# Proc(..., Int32)". The literal also shared the enclosing function's
# ValueId-keyed enum ledger although its ValueIds restart at zero, so an
# Int32 result beside an enum local must stay Int32. A result that does not
# match an explicit annotation must still be rejected as original Crystal does.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-literal-enum-result.XXXXXX")"
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

def raise(message)
  LibC.exit(3)
end

enum RC
  NO_REASON = 0
  END_OF_STACK = 5
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end
'

# Original Crystal rejects two lib funs bound to one C symbol, so each fixture
# declares only the `_Unwind_Backtrace` binding it uses.
LIB_U='lib LibU
  enum RC
    NO_REASON = 0
    END_OF_STACK = 5
  end
  fun backtrace = _Unwind_Backtrace((Void*, Void*) -> RC, Void*) : Int32
end
'
LIB_T='lib LibT
  fun backtrace = _Unwind_Backtrace((Void*, Void*) -> ::RC, Void*) : Int32
end
'

write_case() {
  printf '%s\n%s\n%s\n' "$PRELUDE" "$2" "$3" > "$WORK_DIR/$1.cr"
}

write_case lib_enum_inferred "$LIB_U" '
def go : Nil
  fn = ->(context : Void*, data : Void*) do
    LibU::RC::NO_REASON
  end
  x = 1
  LibU.backtrace(fn, pointerof(x).as(Void*))
end
go
LibC.exit(7)'

write_case lib_enum_annotated "$LIB_U" '
def go : Nil
  fn = ->(context : Void*, data : Void*) : LibU::RC do
    LibU::RC::NO_REASON
  end
  x = 1
  LibU.backtrace(fn, pointerof(x).as(Void*))
end
go
LibC.exit(6)'

write_case toplevel_enum_inferred "$LIB_T" '
def go : Nil
  fn = ->(context : Void*, data : Void*) do
    RC::NO_REASON
  end
  x = 1
  LibT.backtrace(fn, pointerof(x).as(Void*))
end
go
LibC.exit(5)'

write_case int_result_beside_enum_local '' '
def run(f : Int32 -> Int32) : Int32
  f.call(4)
end

def go : Int32
  e = RC::END_OF_STACK
  f = ->(a : Int32) { a }
  run(f)
end
LibC.exit(go)'

write_case annotation_mismatch '' '
fn = -> : Int32 { RC::NO_REASON }'

POSITIVE_CASES=(lib_enum_inferred:7 lib_enum_annotated:6 toplevel_enum_inferred:5
  int_result_beside_enum_local:4)
NEGATIVE_CASE=annotation_mismatch
NEGATIVE_DIAGNOSTIC="expected Proc to return Int32, not RC"

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
      ! grep -qF "$NEGATIVE_DIAGNOSTIC" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
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
  printf '%d proc-literal enum-result case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'proc-literal enum-result cases passed\n'
