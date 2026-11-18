#!/usr/bin/env bash
# Native regression for conditional instance fields declared in an included
# module. Stock Crystal and the current Adamas compiler must read the selected
# typed and inferred fields correctly. Reads of inactive branch fields must
# remain compile errors. An optional baseline compiler can demonstrate the
# pre-fix failure.
#
# Usage:
#   CRYSTAL_BIN=/path/to/crystal ADAMAS_BIN=/path/to/adamas \
#   ADAMAS_BEFORE_BIN=/path/to/baseline/adamas \
#   regression_tests/included_module_conditional_ivar_native_repro.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal || true)}"
ADAMAS_BEFORE_BIN="${ADAMAS_BEFORE_BIN:-}"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
KEEP_WORK_DIR="${KEEP_WORK_DIR:-0}"
DEFAULT_LINK_FLAGS=""
if [[ "$(uname -s)" == "Darwin" ]]; then
  DEFAULT_LINK_FLAGS="-L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld"
fi
STOCK_LINK_FLAGS="${ORIGINAL_CRYSTAL_LINK_FLAGS:-$DEFAULT_LINK_FLAGS}"
ADAMAS_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-$DEFAULT_LINK_FLAGS}"

if [[ -z "$CRYSTAL_BIN" ]]; then
  echo "set CRYSTAL_BIN or install crystal on PATH" >&2
  exit 2
fi
for compiler in "$CRYSTAL_BIN" "$ADAMAS_BIN"; do
  if [[ ! -x "$compiler" ]]; then
    echo "compiler is not executable: $compiler" >&2
    exit 2
  fi
done
if [[ -n "$ADAMAS_BEFORE_BIN" && ! -x "$ADAMAS_BEFORE_BIN" ]]; then
  echo "baseline compiler is not executable: $ADAMAS_BEFORE_BIN" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/included-module-conditional-ivar.XXXXXX")"
cleanup() {
  if [[ "$KEEP_WORK_DIR" == "1" ]]; then
    echo "artifacts: $WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat > "$WORK_DIR/common.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

module IncludedConditionalFields
  {% if flag?(:module_field_alt) %}
    @alt_typed : Int32 = 30
    @alt_inferred = 12
  {% elsif flag?(:darwin) %}
    @darwin_typed : Int32 = 20
    @darwin_inferred = 22
  {% else %}
    @fallback_typed : Int32 = 10
    @fallback_inferred = 32
  {% end %}
end
CR

compile_case() {
  local stage="$1" compiler="$2" variant="$3" source="$4" binary="$5" log="$6"
  local -a args=()
  if [[ "$stage" == "stock" ]]; then
    args=(build --prelude=empty)
    [[ -z "$STOCK_LINK_FLAGS" ]] || args+=("--link-flags=$STOCK_LINK_FLAGS")
  else
    args=(--prelude=empty)
  fi
  if [[ "$variant" == "alternate" ]]; then
    args+=(-D module_field_alt)
  fi
  args+=("$source" -o "$binary")

  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache-$stage" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="$ADAMAS_LINK_FLAGS" \
      "$SAFE_RUNNER" "$compiler" 180 12288 "${args[@]}" >"$log" 2>&1; then
    return 0
  else
    return $?
  fi
}

native_exit_code() {
  local binary="$1" log="$2" status actual
  status=0
  "$SAFE_RUNNER" "$binary" 10 512 >"$log" 2>&1 || status=$?
  actual="$(sed -n 's/^\[EXIT: \([0-9][0-9]*\)\].*/\1/p' "$log" | head -1)"
  if [[ -z "$actual" || "$status" != "$actual" ]]; then
    echo "native run did not produce a clean exit marker (status $status)" >&2
    cat "$log" >&2
    return 1
  fi
  printf '%s\n' "$actual"
}

run_expected_exit() {
  local stage="$1" variant="$2" binary="$3" log="$4" actual
  if ! actual="$(native_exit_code "$binary" "$log")"; then
    echo "FAIL $stage/$variant: native program did not exit cleanly" >&2
    return 1
  fi
  if [[ "$actual" != "42" ]]; then
    echo "FAIL $stage/$variant: native exit was $actual, expected 42" >&2
    cat "$log" >&2
    return 1
  fi
  echo "PASS $stage/$variant: native exit 42"
}

expect_baseline_red() {
  local variant="$1" active_field="$2" binary log
  binary="$WORK_DIR/baseline-$variant"
  log="$WORK_DIR/baseline-$variant.compile.log"
  if compile_case baseline "$ADAMAS_BEFORE_BIN" "$variant" "$WORK_DIR/positive.cr" "$binary" "$log"; then
    actual="$(native_exit_code "$binary" "$WORK_DIR/baseline-$variant.run.log")" || {
      echo "FAIL baseline/$variant: compiled, but its native run did not exit cleanly" >&2
      return 1
    }
    if [[ "$actual" == "42" ]]; then
      echo "FAIL baseline/$variant: unexpectedly produced the correct native result" >&2
      return 1
    fi
    echo "RED baseline/$variant: native exit $actual (expected 42)"
    return 0
  fi
  if grep -Fq "can't infer the type of instance variable '$active_field' of ConditionalFieldOwner" "$log"; then
    echo "RED baseline/$variant: active field $active_field is rejected"
  elif grep -Fq 'method ConditionalFieldOwner#selected_total must return Int32, but it is returning Void' "$log"; then
    echo "RED baseline/$variant: selected field read leaves selected_total as Void"
  else
    echo "FAIL baseline/$variant: compile failed without the expected missing-field/lost-result diagnostic" >&2
    cat "$log" >&2
    return 1
  fi
  if grep -Eiq 'syntax error|internal compiler error|segmentation fault|stack overflow' "$log"; then
    echo "FAIL baseline/$variant: failure was not an ordinary missing-field failure" >&2
    cat "$log" >&2
    return 1
  fi
}

expect_inactive_rejected() {
  local stage="$1" compiler="$2" variant="$3" inactive_field="$4"
  local binary log
  binary="$WORK_DIR/$stage-$variant-negative"
  log="$WORK_DIR/$stage-$variant-negative.compile.log"
  if compile_case "$stage" "$compiler" "$variant" "$WORK_DIR/negative.cr" "$binary" "$log"; then
    echo "FAIL $stage/$variant: inactive field $inactive_field compiled" >&2
    return 1
  fi
  if grep -Fq "can't infer the type of instance variable '$inactive_field' of ConditionalFieldOwner" "$log"; then
    :
  elif grep -Fq 'method ConditionalFieldOwner#inactive_total must return Int32, but it is returning Void' "$log"; then
    :
  else
    echo "FAIL $stage/$variant: rejection did not name inactive field $inactive_field" >&2
    cat "$log" >&2
    return 1
  fi
  if grep -Eiq 'syntax error|internal compiler error|segmentation fault|stack overflow' "$log"; then
    echo "FAIL $stage/$variant: inactive-field control failed for an unrelated compiler error" >&2
    cat "$log" >&2
    return 1
  fi
  echo "PASS $stage/$variant: inactive field $inactive_field is rejected"
}

run_positive_stage() {
  local stage="$1" compiler="$2" variant="$3"
  local binary log
  binary="$WORK_DIR/$stage-$variant"
  log="$WORK_DIR/$stage-$variant.compile.log"
  if ! compile_case "$stage" "$compiler" "$variant" "$WORK_DIR/positive.cr" "$binary" "$log"; then
    echo "FAIL $stage/$variant: positive native source did not compile" >&2
    cat "$log" >&2
    return 1
  fi
  run_expected_exit "$stage" "$variant" "$binary" "$WORK_DIR/$stage-$variant.run.log"
}

for variant in darwin alternate; do
  if [[ "$variant" == "alternate" ]]; then
    active_field="@alt_typed"
    selected_inferred="@alt_inferred"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      inactive_field="@darwin_typed"
    else
      inactive_field="@fallback_typed"
    fi
  else
    if [[ "$(uname -s)" == "Darwin" ]]; then
      active_field="@darwin_typed"
      selected_inferred="@darwin_inferred"
      inactive_field="@alt_typed"
    else
      active_field="@fallback_typed"
      selected_inferred="@fallback_inferred"
      inactive_field="@alt_typed"
    fi
  fi

  cat "$WORK_DIR/common.cr" > "$WORK_DIR/positive.cr"
  cat >> "$WORK_DIR/positive.cr" <<CR
class ConditionalFieldOwner
  include IncludedConditionalFields

  def selected_total : Int32
    $active_field + $selected_inferred
  end
end

LibC.exit(ConditionalFieldOwner.new.selected_total)
CR

  cat "$WORK_DIR/common.cr" > "$WORK_DIR/negative.cr"
  cat >> "$WORK_DIR/negative.cr" <<CR
class ConditionalFieldOwner
  include IncludedConditionalFields

  def inactive_total : Int32
    $inactive_field
  end
end

LibC.exit(ConditionalFieldOwner.new.inactive_total)
CR

  run_positive_stage stock "$CRYSTAL_BIN" "$variant"
  if [[ -n "$ADAMAS_BEFORE_BIN" ]]; then
    expect_baseline_red "$variant" "$active_field"
  fi
  run_positive_stage current "$ADAMAS_BIN" "$variant"
  expect_inactive_rejected stock "$CRYSTAL_BIN" "$variant" "$inactive_field"
  if [[ -n "$ADAMAS_BEFORE_BIN" ]]; then
    expect_inactive_rejected baseline "$ADAMAS_BEFORE_BIN" "$variant" "$inactive_field"
  fi
  expect_inactive_rejected current "$ADAMAS_BIN" "$variant" "$inactive_field"
done

if [[ -n "$ADAMAS_BEFORE_BIN" ]]; then
  echo "PASS: included conditional module fields match stock; baseline red, current green"
else
  echo "PASS: included conditional module fields match stock and current Adamas"
fi
