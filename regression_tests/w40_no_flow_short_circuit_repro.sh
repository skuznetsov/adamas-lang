#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
baseline="${2:-${ADAMAS_BASELINE_BIN:-}}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
fixtures="$root/regression_tests/fixtures/w40_no_flow_short_circuit"
work="$(mktemp -d "${TMPDIR:-/tmp}/w40-no-flow-short-circuit.XXXXXX")"
cleanup() {
  if [[ "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'artifacts retained %s\n' "$work" >&2
  else
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

compile() {
  local stage="$1" compiler="$2" fixture="$3" rc=0
  local out="$work/$stage-$fixture"
  local log="$out.compile.log"
  if [[ "$stage" == original ]]; then
    local -a args=(build --prelude=empty --no-debug)
    if [[ "$(uname -s)" == Darwin ]]; then args+=(--link-flags=-fuse-ld=/usr/bin/ld); fi
    "$safe" "$compiler" 90 8192 "${args[@]}" "$fixtures/$fixture.cr" -o "$out" </dev/null >"$log" 2>&1 || rc=$?
  else
    "$safe" "$compiler" 90 8192 "$fixtures/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$out" </dev/null >"$log" 2>&1 || rc=$?
  fi
  printf '%s\n' "$rc" >"$out.status"
  printf '%s\n' "$out"
}
run_positive() {
  local stage="$1" compiler="$2" fixture="$3" expected="$4" out
  out="$(compile "$stage" "$compiler" "$fixture")"
  if [[ "$(cat "$out.status")" != 0 || ! -x "$out" ]]; then
    cat "$out.compile.log" >&2
    printf 'FAIL[%s:%s] expected compile success\n' "$stage" "$fixture" >&2
    return 1
  fi
  if ! "$safe" "$out" 5 512 </dev/null >"$out.stdout" 2>"$out.stderr"; then
    cat "$out.stderr" >&2
    printf 'FAIL[%s:%s] runtime failed\n' "$stage" "$fixture" >&2
    return 1
  fi
  if ! cmp -s "$fixtures/$expected" "$out.stdout"; then
    diff -u "$fixtures/$expected" "$out.stdout" >&2 || true
    printf 'FAIL[%s:%s] output mismatch\n' "$stage" "$fixture" >&2
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$fixture"
}
run_rejection() {
  local stage="$1" compiler="$2" fixture="$3" required="$4" out
  out="$(compile "$stage" "$compiler" "$fixture")"
  if [[ "$(cat "$out.status")" != 1 || -x "$out" ]] ||
      ! rg -qi "$required" "$out.compile.log"; then
    cat "$out.compile.log" >&2
    printf 'FAIL[%s:%s] expected strict rejection matching %s\n' "$stage" "$fixture" "$required" >&2
    return 1
  fi
  printf 'PASS_REJECT[%s:%s]\n' "$stage" "$fixture"
}

run_differential_rejection() {
  local left_stage="$1" left_compiler="$2" right_stage="$3" right_compiler="$4" fixture="$5" left_out right_out
  left_out="$(compile "$left_stage" "$left_compiler" "$fixture")"
  right_out="$(compile "$right_stage" "$right_compiler" "$fixture")"
  for entry in "$left_stage:$left_out" "$right_stage:$right_out"; do
    local stage="${entry%%:*}" out="${entry#*:}"
    if [[ "$(cat "$out.status")" != 1 || -x "$out" ]] || ! rg -qi '^error:' "$out.compile.log"; then
      cat "$out.compile.log" >&2
      printf 'FAIL_DIFF_REJECT[%s:%s] expected compile rejection with no output\n' "$stage" "$fixture" >&2
      return 1
    fi
  done
  printf 'PASS_DIFF_REJECT[%s:%s:%s]\n' "$left_stage" "$right_stage" "$fixture"
}

check_stage() {
  local stage="$1" compiler="$2"
  run_positive "$stage" "$compiler" nil_or_noreturn nil_or_noreturn.expected
  run_positive "$stage" "$compiler" shadowed_noreturn shadowed_noreturn.expected
  run_positive "$stage" "$compiler" nested_flow nested_flow.expected
  run_rejection "$stage" "$compiler" wrong_result 'must return String.*Int32'
  if [[ "$stage" == original ]]; then
    run_rejection "$stage" "$compiler" invalid_rhs 'undefined.*unknown_no_flow_rhs'
  else
    run_rejection "$stage" "$compiler" invalid_rhs 'error:'
  fi
}

check_stage original "$original"
if [[ "${ONLY_ORIGINAL:-0}" != 1 ]]; then
  check_stage candidate "$candidate"
  if [[ -n "$baseline" ]]; then
    run_differential_rejection baseline "$baseline" candidate "$candidate" invalid_rhs
  fi
fi
printf 'w40_no_flow_short_circuit_repro PASS\n'
