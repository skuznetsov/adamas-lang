#!/usr/bin/env bash
# Original-first checks for direct **NamedTuple literal call binding.
# Cold-cache HIR coverage lives in spec/hir/double_splat_literal_call_binding_spec.cr.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
[[ -x "$SAFE_RUNNER" && -n "$ORIGINAL" && -x "$ORIGINAL" ]] || {
  echo "installed Crystal or SAFE runner is unavailable" >&2
  exit 2
}
if [[ "${ORIGINAL_ONLY:-0}" != 1 && ! -x "$COMPILER" ]]; then
  echo "candidate compiler is unavailable" >&2
  exit 2
fi
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
else
  CRYSTAL_STDLIB="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$ORIGINAL" 10 512 env CRYSTAL_PATH)"
fi
stdlib_found=0
IFS=: read -r -a stdlib_paths <<<"$CRYSTAL_STDLIB"
for stdlib_entry in "${stdlib_paths[@]}"; do
  if [[ -d "$stdlib_entry" ]]; then
    stdlib_found=1
    break
  fi
done
[[ "$stdlib_found" == 1 ]] || { echo "installed Crystal stdlib is unavailable" >&2; exit 2; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/double-splat-literal-call.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
@[Link("c")]
lib DoubleSplatLiteralBindingC
  fun putchar(value : Int32) : Int32
end

def mark(value : Int32, marker : Int32) : Int32
  DoubleSplatLiteralBindingC.putchar(marker)
  value
end

def keyword_target(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
  DoubleSplatLiteralBindingC.putchar(first)
  DoubleSplatLiteralBindingC.putchar(second)
  DoubleSplatLiteralBindingC.putchar(yield)
end

def narrow_keyword_target(*, first : UInt8, &block : -> Int32) : Int32
  DoubleSplatLiteralBindingC.putchar(first.to_i32)
  DoubleSplatLiteralBindingC.putchar(yield)
end

def reassigned_keyword_target(marker : Int32, *, second : Int32) : Int32
  DoubleSplatLiteralBindingC.putchar(marker)
  DoubleSplatLiteralBindingC.putchar(second)
end

def assigned_keyword_target(marker : NamedTuple(second: Int32), *, second : Int32) : Int32
  DoubleSplatLiteralBindingC.putchar(marker[:second])
  DoubleSplatLiteralBindingC.putchar(second)
end

def hoist_order_target(marker : Int32, *, keyword : Int32) : Int32
  DoubleSplatLiteralBindingC.putchar(80)
end

def mixed_slot_target(first : Int32, second : Int32, *, third : UInt8, extra : Int32 = 68, &block : -> Int32) : Int32
  DoubleSplatLiteralBindingC.putchar(first)
  DoubleSplatLiteralBindingC.putchar(second)
  DoubleSplatLiteralBindingC.putchar(third.to_i32)
  DoubleSplatLiteralBindingC.putchar(extra)
  DoubleSplatLiteralBindingC.putchar(yield)
end

class HoistOrderReceiver
  def accept(*, keyword : Int32) : Int32
    DoubleSplatLiteralBindingC.putchar(80)
  end
end

class KeywordCallReceiver
  def accept(marker : Int32, *, second : Int32) : Int32
    DoubleSplatLiteralBindingC.putchar(marker)
    DoubleSplatLiteralBindingC.putchar(second)
  end
end

macro ignore_double_splat(*args, **options)
  DoubleSplatLiteralBindingC.putchar(77)
end

module DoubleSplatMacroScope
  macro ignore_arguments(*args, **options)
    DoubleSplatLiteralBindingC.putchar(77)
  end
end

class DoubleSplatMacroParent
  macro ignore_arguments(*args, **options)
    DoubleSplatLiteralBindingC.putchar(77)
  end
end

class DoubleSplatMacroChild < DoubleSplatMacroParent
end

keyword_target(**{second: mark(66, 97), first: mark(65, 98)}) { mark(67, 99) }
options = {second: mark(69, 100), first: mark(68, 101)}
keyword_target(**options) { mark(70, 102) }
keyword_target(**{first: mark(65, 103)}) { mark(67, 104) }
keyword_target(**{second: mark(66, 106)}, first: mark(65, 105)) { mark(67, 107) }
keyword_target(**{second: mark(66, 108)}, **{first: mark(65, 109)}) { mark(67, 110) }
narrow_keyword_target(first: 65) { 66 }
options = {first: 65}
reassigned_keyword_target((options = {second: 66}; 65), **options)
options = {first: 65}
assigned_keyword_target(options = {second: 66}, **options)
options = {first: 65}
((options = {second: 66}); KeywordCallReceiver.new).accept(65, **options)
hoist_order_target(mark(65, 65), **{keyword: mark(66, 66)})
(mark(65, 65); HoistOrderReceiver.new).accept(**{keyword: mark(66, 66)})
hoist_order_target(*{mark(65, 65)}, **{keyword: mark(66, 66)})
mixed_slot_target(*{65, 66}, third: 67) { 69 }
mixed_slot_target(*{65, 66}, **{extra: 68}, third: 67) { 69 }
# Macro arguments remain AST data: none of these X markers may execute.
ignore_double_splat(**{first: mark(88, 88)})
DoubleSplatMacroScope.ignore_arguments(**{first: mark(88, 88)})
DoubleSplatMacroChild.ignore_arguments(**{first: mark(88, 88)})
DoubleSplatLiteralBindingC.putchar(10)
CRYSTAL
printf 'abABcCdeDEfFgADhCjiABkClmABnCABABBBABBAPBAPABPABCDEABCDEMMM\n' >"$WORK_DIR/positive.expected"

cat >"$WORK_DIR/unknown_key.cr" <<'CRYSTAL'
def keyword_target(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
  yield
end

keyword_target(**{first: 65, unknown: 66}) { 67 }
CRYSTAL

cat >"$WORK_DIR/missing_required_key.cr" <<'CRYSTAL'
def keyword_target(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
  yield
end

keyword_target(**{second: 66}) { 67 }
CRYSTAL

cat >"$WORK_DIR/wrong_key_type.cr" <<'CRYSTAL'
def keyword_target(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
  yield
end

keyword_target(**{first: true}) { 67 }
CRYSTAL

cat >"$WORK_DIR/double_splat_literal_not_autocast.cr" <<'CRYSTAL'
def keyword_target(*, first : UInt8, &block : -> Int32) : Int32
  yield
end
keyword_target(**{first: 65}) { 67 }
CRYSTAL

cat >"$WORK_DIR/double_splat_local_not_autocast.cr" <<'CRYSTAL'
def keyword_target(*, first : UInt8, &block : -> Int32) : Int32
  yield
end
options = {first: 65}
keyword_target(**options) { 67 }
CRYSTAL

cat >"$WORK_DIR/positional_splat_field_not_autocast.cr" <<'CRYSTAL'
def keyword_target(first : UInt8, second : Int32, *, third : UInt8, &block : -> Int32) : Int32
  yield
end
keyword_target(*{65, 66}, third: 67) { 69 }
CRYSTAL

cat >"$WORK_DIR/duplicate_explicit_and_splat_key.cr" <<'CRYSTAL'
def keyword_target(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
  yield
end

keyword_target(**{first: 65}, first: 66) { 67 }
CRYSTAL

cat >"$WORK_DIR/duplicate_splat_keys.cr" <<'CRYSTAL'
def keyword_target(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
  yield
end

keyword_target(**{first: 65}, **{first: 66}) { 67 }
CRYSTAL

cat >"$WORK_DIR/hoisted_assignment_duplicate_keys.cr" <<'CRYSTAL'
def keyword_target(*, first : Int32 = 65, second : Int32 = 66) : Int32
  first + second
end
options = {first: 65}
# The complex second operand is hoisted before the simple first operand is read.
keyword_target(**options, **(options = {second: 66}))
CRYSTAL

cat >"$WORK_DIR/double_splat_array.cr" <<'CRYSTAL'
def keyword_target(*, first : Int32) : Int32
  first
end

values = [65]
keyword_target(**values)
CRYSTAL

cat >"$WORK_DIR/double_splat_tuple.cr" <<'CRYSTAL'
def keyword_target(*, first : Int32) : Int32
  first
end

values = {65}
keyword_target(**values)
CRYSTAL

ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)

compile_case() {
  local stage="$1" name="$2" status=0
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$ORIGINAL" 180 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    command=("$COMPILER" 180 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
    "$SAFE_RUNNER" "${command[@]}" "$WORK_DIR/$name.cr" -o "$WORK_DIR/$stage.$name.bin" \
    >"$WORK_DIR/$stage.$name.compile.log" 2>&1 || status=$?
  return "$status"
}

fail() {
  echo "FAIL: $*" >&2
  return 1
}

check_positive() {
  local stage="$1"
  compile_case "$stage" positive || {
    cat "$WORK_DIR/$stage.positive.compile.log" >&2
    fail "[$stage/positive] expected successful **NamedTuple calls"
    return 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$stage.positive.bin" 10 512 \
    >"$WORK_DIR/$stage.stdout" 2>"$WORK_DIR/$stage.run.log" || {
      cat "$WORK_DIR/$stage.run.log" >&2
      fail "[$stage/positive] runtime failed"
      return 1
    }
  diff -u "$WORK_DIR/positive.expected" "$WORK_DIR/$stage.stdout" || {
    fail "[$stage/positive] output/order/count differs"
    return 1
  }
}

check_rejection() {
  local stage="$1" name="$2" expected="$3" status=0
  compile_case "$stage" "$name" || status=$?
  if [[ "$status" != 1 || -e "$WORK_DIR/$stage.$name.bin" ]]; then
    cat "$WORK_DIR/$stage.$name.compile.log" >&2
    fail "[$stage/$name] expected semantic rejection without an executable"
    return 1
  fi
  python3 - "$WORK_DIR/$stage.$name.compile.log" "$expected" <<'PY_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace").lower()
assert "error" in text, text
assert sys.argv[2].lower() in text, text
for forbidden in ("syntax error", "parser errors", "expected named argument", "internal compiler error", "unhandled exception"):
    assert forbidden not in text, text
PY_REJECT
}

negative_cases=(
  "unknown_key:unknown"
  "missing_required_key:keyword_target"
  # Crystal reports the required key as missing when a supplied value has an
  # incompatible type; the call must still be rejected before code generation.
  "wrong_key_type:first"
  "double_splat_literal_not_autocast:first"
  "double_splat_local_not_autocast:first"
  "positional_splat_field_not_autocast:keyword_target"
  "duplicate_explicit_and_splat_key:first"
  "duplicate_splat_keys:first"
  "hoisted_assignment_duplicate_keys:second"
  "double_splat_array:array"
  "double_splat_tuple:tuple"
)

# Do not reach the candidate unless every original source/runtime contract passes.
original_failures=0
check_positive original || original_failures=1
for item in "${negative_cases[@]}"; do
  check_rejection original "${item%%:*}" "${item#*:}" || original_failures=1
done
if [[ "$original_failures" != 0 ]]; then
  fail "original Crystal gate failed; candidate was not run"
  exit 1
fi
if [[ "${ORIGINAL_ONLY:-0}" == 1 ]]; then
  echo "PASS: original Crystal **NamedTuple literal/local binding controls"
  exit 0
fi

candidate_failures=0
check_positive candidate || candidate_failures=1
for item in "${negative_cases[@]}"; do
  check_rejection candidate "${item%%:*}" "${item#*:}" || candidate_failures=1
done
if [[ "$candidate_failures" != 0 ]]; then
  fail "candidate failed one or more **NamedTuple binding controls"
  exit 1
fi
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
echo "PASS: literal/local **NamedTuple binding, source evaluation order, named slots, block separation, and strict rejection"
