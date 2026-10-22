#!/usr/bin/env bash
# Original-first regression for Proc constructor receiver ownership facts.
# Every compiler and generated program is supervised by scripts/run_safe.sh.
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [adamas-compiler]" >&2
  exit 2
fi

ROOT_DIR="${ADAMAS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
ROOT_DIR="$(cd "$ROOT_DIR" && pwd -P)"
FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/proc_constructor_receiver_ownership_fixtures"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
SAFE_RUN="${ADAMAS_RUN_SAFE:-${RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ "$ORIGINAL_HINT" == */* ]]; then
  ORIGINAL="$ORIGINAL_HINT"
else
  ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"
fi
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-4096}"

[[ -x "$COMPILER" && -x "$ORIGINAL" && -x "$SAFE_RUN" && -d "$FIXTURE_DIR" ]] || {
  echo "candidate, original Crystal, SAFE runner, or fixture directory is unavailable" >&2
  echo "set ORIGINAL_CRYSTAL_BIN to the original Crystal executable when needed" >&2
  exit 2
}

POSITIVES=(
  rooted_proc_base_shadowed_by_owner_alias
  arrow_alias_callback
  custom_new_returns_int32
  ordinary_generic_box_new
  raw_pair_proc_new
  rooted_proc_signature_owner_alias
  rooted_proc_signature_owner_alias_arrow
  rooted_proc_signature_owner_alias_raw_pair
  proc_new_source_def_int32_then_int64
  proc_new_source_def_int64_then_int32
  custom_proc_new_self_returns_int32
  custom_proc_new_self_inferred_int32
  nested_proc_new_block_result
  proc_new_default_result_accept_int32
  proc_new_splat_result_accept_int32
)
NEGATIVES=(proc_new_default_result_reject_proc)
ORIGINAL_NEGATIVE_MARKERS=("not Int32")
CANDIDATE_NEGATIVE_MARKERS=("no overload matches accept_proc" "argument types (Int32)")

for name in "${POSITIVES[@]}"; do
  [[ -s "$FIXTURE_DIR/$name.cr" && -f "$FIXTURE_DIR/$name.expected" ]] || {
    echo "missing positive fixture or expected bytes: $name" >&2
    exit 2
  }
done
for name in "${NEGATIVES[@]}"; do
  [[ -s "$FIXTURE_DIR/$name.cr" ]] || {
    echo "missing negative source fixture: $name" >&2
    exit 2
  }
done
[[ -s "$FIXTURE_DIR/proc_new_default_result_reject_proc.reject" ]] || {
  echo "missing negative fixture semantic marker" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-constructor-receiver-ownership.XXXXXX")"
ORIGINAL_LINK_ARGS=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$WORK_DIR"/cache.* "$WORK_DIR"/*.program
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

check_footer() {
  local log="$1" expected_code="$2"
  tail -n 2 "$log" | awk -v code="$expected_code" '
    NR == 1 {
      pattern = "^\\[EXIT: " code "\\] after ~[0-9]+(\\.[0-9]+)? ?s$"
      if ($0 !~ pattern) bad = 1
    }
    NR == 2 {
      pattern = "^\\[RUN_SAFE_RESOURCE\\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=" code "( |$)"
      if ($0 !~ pattern) bad = 1
    }
    END { exit (NR == 2 && !bad ? 0 : 1) }
  '
}

contains_fatal_diagnostic() {
  grep -Eiq 'parse error|sigsegv|segmentation fault|stack overflow|bus error|llvm error|unhandled exception|compiler bug' "$1"
}

compile_case() {
  local stage="$1" compiler="$2" name="$3"
  local source="$FIXTURE_DIR/$name.cr"
  local cache="$WORK_DIR/cache.$stage.$name"
  local -a args run_env
  COMPILE_BINARY="$WORK_DIR/$stage.$name.program"
  COMPILE_LOG="$WORK_DIR/$stage.$name.compile.log"
  COMPILE_STATUS=0
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    args=(build --no-debug --prelude=empty "${ORIGINAL_LINK_ARGS[@]}" "$source" -o "$COMPILE_BINARY")
  else
    args=("$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$COMPILE_BINARY")
  fi
  run_env=("CRYSTAL_CACHE_DIR=$cache")
  if [[ "$stage" == candidate ]]; then
    run_env+=(ADAMAS_LLVM_CACHE=0)
    if [[ "$(uname -s)" == Darwin ]]; then
      run_env+=("ADAMAS_EXTRA_LINK_FLAGS=${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
    fi
  fi

  if env "${run_env[@]}" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "${args[@]}" >"$COMPILE_LOG" 2>&1; then
    COMPILE_STATUS=0
  else
    COMPILE_STATUS=$?
  fi
}

fail_with_log() {
  local stage="$1" name="$2" message="$3" log="$4"
  echo "FAIL[$stage:$name]: $message" >&2
  if [[ -f "$log" ]]; then
    tail -40 "$log" >&2 || true
  fi
  return 1
}

run_positive() {
  local stage="$1" compiler="$2" name="$3"
  local stdout="$WORK_DIR/$stage.$name.stdout"
  local runtime_log="$WORK_DIR/$stage.$name.runtime.log"
  local status=0

  compile_case "$stage" "$compiler" "$name"
  if [[ "$COMPILE_STATUS" -ne 0 ]]; then
    fail_with_log "$stage" "$name" "compile exited $COMPILE_STATUS" "$COMPILE_LOG"
  fi
  if ! check_footer "$COMPILE_LOG" 0; then
    fail_with_log "$stage" "$name" "compile SAFE footer is missing or nonzero" "$COMPILE_LOG"
  fi
  if contains_fatal_diagnostic "$COMPILE_LOG"; then
    fail_with_log "$stage" "$name" "compile log contains a fatal diagnostic" "$COMPILE_LOG"
  fi
  if [[ ! -x "$COMPILE_BINARY" ]]; then
    fail_with_log "$stage" "$name" "successful compile did not emit an executable" "$COMPILE_LOG"
  fi

  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$COMPILE_BINARY" 5 512 >"$stdout" 2>"$runtime_log"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -ne 0 ]] || ! check_footer "$runtime_log" 0; then
    fail_with_log "$stage" "$name" "runtime failed or SAFE footer is nonzero (exit $status)" "$runtime_log"
  fi
  if contains_fatal_diagnostic "$runtime_log"; then
    fail_with_log "$stage" "$name" "runtime log contains a fatal diagnostic" "$runtime_log"
  fi
  if ! cmp -s "$FIXTURE_DIR/$name.expected" "$stdout"; then
    fail_with_log "$stage" "$name" "stdout differs from frozen fixture bytes" "$runtime_log"
  fi
  if [[ "$stage" == candidate ]] && ! cmp -s "$WORK_DIR/original.$name.stdout" "$stdout"; then
    fail_with_log "$stage" "$name" "stdout differs byte-for-byte from original Crystal" "$runtime_log"
  fi
  echo "PASS[$stage:$name] stdout matches expected bytes"
}

run_negative() {
  local stage="$1" compiler="$2" name="$3"
  local status marker
  local -a markers

  compile_case "$stage" "$compiler" "$name"
  if [[ "$COMPILE_STATUS" -ne 1 ]]; then
    fail_with_log "$stage" "$name" "expected semantic compile rejection (exit 1), got $COMPILE_STATUS" "$COMPILE_LOG"
  fi
  if ! check_footer "$COMPILE_LOG" 1; then
    fail_with_log "$stage" "$name" "rejection SAFE footer is missing or not exit 1" "$COMPILE_LOG"
  fi
  if [[ -e "$COMPILE_BINARY" || -L "$COMPILE_BINARY" ]]; then
    fail_with_log "$stage" "$name" "rejected compile left an executable artifact" "$COMPILE_LOG"
  fi
  if contains_fatal_diagnostic "$COMPILE_LOG"; then
    fail_with_log "$stage" "$name" "rejection came with a fatal or parser diagnostic" "$COMPILE_LOG"
  fi
  if ! grep -Eiq '(^|[[:space:]])error:' "$COMPILE_LOG"; then
    fail_with_log "$stage" "$name" "semantic error diagnostic is missing" "$COMPILE_LOG"
  fi
  if [[ "$stage" == original ]]; then
    markers=("${ORIGINAL_NEGATIVE_MARKERS[@]}")
  else
    markers=("${CANDIDATE_NEGATIVE_MARKERS[@]}")
  fi
  for marker in "${markers[@]}"; do
    if [[ -z "$marker" ]] || ! grep -Fqi -- "$marker" "$COMPILE_LOG"; then
      fail_with_log "$stage" "$name" "semantic rejection marker is missing: $marker" "$COMPILE_LOG"
    fi
  done
  echo "PASS[$stage:$name] semantic rejection markers present; no executable emitted"
}

qualify_stage() {
  local stage="$1" compiler="$2" name
  for name in "${POSITIVES[@]}"; do
    run_positive "$stage" "$compiler" "$name"
  done
  for name in "${NEGATIVES[@]}"; do
    run_negative "$stage" "$compiler" "$name"
  done
  printf '%s_PASS_COMPLETE positives=%s negatives=%s\n' "$stage" "${#POSITIVES[@]}" "${#NEGATIVES[@]}"
}

# Gate every candidate compile on the complete original-Crystal stage.
echo "ORIGINAL_CRYSTAL=$ORIGINAL"
qualify_stage original "$ORIGINAL"
echo "ORIGINAL_PASS_COMPLETE; starting Adamas candidate"
qualify_stage candidate "$COMPILER"
