#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURE_DIR="$ROOT_DIR/regression_tests/fixtures/raw_macro_flag_branch"
SAFE_RUNNER="${ADAMAS_RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
ADAMAS_BIN="${1:?usage: run_five_cases.sh /path/to/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/threadlike-raw-flags.XXXXXX")"

cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

[[ -x "$SAFE_RUNNER" ]] || { echo "safe runner not found: $SAFE_RUNNER" >&2; exit 2; }
[[ -x "$ORIGINAL_CRYSTAL" ]] || { echo "original Crystal compiler not found" >&2; exit 2; }
[[ -x "$ADAMAS_BIN" ]] || { echo "Adamas compiler not found: $ADAMAS_BIN" >&2; exit 2; }

candidate_link_env=(ADAMAS_LLVM_CACHE=0)
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link_flags="${ADAMAS_ORIGINAL_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
  candidate_link_env=("ADAMAS_EXTRA_LINK_FLAGS=${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
fi

compile_and_check() {
  local stage="$1" case_name="$2" expected_file="$3" status=0
  shift 3
  local binary="$WORK_DIR/$stage.$case_name"
  local log="$binary.compile.log"

  if [[ "$stage" == stock ]]; then
    local -a stock_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    if [[ "$(uname -s)" == Darwin ]]; then
      CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$case_name" \
        "${stock_env[@]}" "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 120 4096 build \
        "$FIXTURE_DIR/threadlike_accessor_branch.cr" --prelude=empty "$@" \
        --link-flags="$stock_link_flags" -o "$binary" >"$log" 2>&1 || status=$?
    else
      CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$case_name" \
        "${stock_env[@]}" "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL" 120 4096 build \
        "$FIXTURE_DIR/threadlike_accessor_branch.cr" --prelude=empty "$@" \
        -o "$binary" >"$log" 2>&1 || status=$?
    fi
  else
    local -a mode_env
    if [[ "$stage" == eager ]]; then
      mode_env=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${candidate_link_env[@]}")
    else
      mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO "${candidate_link_env[@]}")
    fi
    CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$case_name" \
      "${mode_env[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 \
      "$FIXTURE_DIR/threadlike_accessor_branch.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache "$@" -o "$binary" >"$log" 2>&1 || status=$?
  fi

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL: $stage compile for $case_name (exit $status)" >&2
    tail -60 "$log" >&2
    return 1
  fi

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
      >"$binary.stdout" 2>"$binary.run.log"; then
    echo "FAIL: $stage run for $case_name" >&2
    cat "$binary.run.log" >&2
    return 1
  fi

  if ! cmp -s "$expected_file" "$binary.stdout"; then
    echo "FAIL: $stage output for $case_name" >&2
    diff -u "$expected_file" "$binary.stdout" >&2 || true
    return 1
  fi
}

cases=(default preview_mt without_mt without_mt_execution_context preview_mt_execution_context)
for case_name in "${cases[@]}"; do
  case "$case_name" in
    default)
      case_flags=(--no-debug)
      expected_name=expected_none.stdout
      ;;
    preview_mt)
      case_flags=(--no-debug -D preview_mt)
      expected_name=expected_preview_mt.stdout
      ;;
    without_mt)
      case_flags=(--no-debug -D without_mt)
      expected_name=expected_without_mt.stdout
      ;;
    without_mt_execution_context)
      case_flags=(--no-debug -D without_mt -D execution_context)
      expected_name=expected_without_mt_execution_context.stdout
      ;;
    preview_mt_execution_context)
      case_flags=(--no-debug -D preview_mt -D execution_context)
      expected_name=expected_preview_mt_execution_context.stdout
      ;;
  esac

  expected_file="$FIXTURE_DIR/$expected_name"
  for stage in stock lazy eager; do
    compile_and_check "$stage" "$case_name" "$expected_file" "${case_flags[@]}"
    printf 'PASS: %s %s\n' "$stage" "$case_name"
  done
done

printf 'PASS: raw Thread-like macro branches match stock in lazy and eager Adamas modes\n'
