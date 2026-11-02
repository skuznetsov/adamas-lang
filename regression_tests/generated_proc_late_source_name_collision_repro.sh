#!/usr/bin/env bash
# Keep source methods published after generated Procs in a separate namespace.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
FIXTURE_DIR="$SCRIPT_DIR/generated_proc_late_source_name_collision"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ "$ORIGINAL_HINT" == */* ]]; then
  ORIGINAL="$ORIGINAL_HINT"
else
  ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"
fi
[[ -x "$SAFE_RUN" && -x "$ADAMAS_BIN" && -n "$ORIGINAL" && -x "$ORIGINAL" ]] || {
  printf 'usage: ADAMAS_BIN=/path/to/adamas ORIGINAL_CRYSTAL_BIN=/path/to/crystal %s\n' "$0" >&2
  exit 2
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/generated-proc-name-collision.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"
if [[ -z "$CRYSTAL_STDLIB" ]]; then
  path_status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$ORIGINAL" 10 1024 env CRYSTAL_PATH \
    >"$WORK/crystal_path" 2>"$WORK/crystal_path.log" || path_status=$?
  if [[ "$path_status" -ne 0 ]]; then
    printf 'could not obtain CRYSTAL_PATH from original Crystal\n' >&2
    cat "$WORK/crystal_path.log" >&2
    exit 2
  fi
  CRYSTAL_STDLIB="$(cat "$WORK/crystal_path")"
fi
[[ -n "$CRYSTAL_STDLIB" ]] || {
  printf 'CRYSTAL_PATH is unavailable; set it or use an original Crystal with env CRYSTAL_PATH\n' >&2
  exit 2
}
export CRYSTAL_PATH="$CRYSTAL_STDLIB"

ORIGINAL_LINK_ARGS=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

check_stage() {
  local stage="$1" case_name="$2"
  local source="$FIXTURE_DIR/$case_name.cr"
  local expected="$FIXTURE_DIR/$case_name.expected"
  local binary="$WORK/$stage.$case_name"
  local compile_log="$WORK/$stage.$case_name.compile.log"
  local runtime_stdout="$WORK/$stage.$case_name.stdout"
  local runtime_stderr="$WORK/$stage.$case_name.stderr"
  local status=0

  if [[ "$stage" == stock ]]; then
    CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$case_name" \
      "$SAFE_RUN" "$ORIGINAL" 180 8192 build --prelude=empty \
      --no-debug "${ORIGINAL_LINK_ARGS[@]}" "$source" -o "$binary" \
      >"$compile_log" 2>&1 || status=$?
  else
    CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$case_name" ADAMAS_LLVM_CACHE=0 \
      "$SAFE_RUN" "$ADAMAS_BIN" 180 8192 "$source" --no-prelude \
      --no-debug --no-ast-cache --no-llvm-cache -o "$binary" \
      >"$compile_log" 2>&1 || status=$?
  fi
  if [[ "$status" -ne 0 || ! -x "$binary" ]]; then
    printf 'COMPILE_FAIL[%s:%s]\n' "$stage" "$case_name" >&2
    tail -n 40 "$compile_log" >&2 || true
    return 1
  fi

  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$binary" 5 512 \
      >"$runtime_stdout" 2>"$runtime_stderr"; then
    printf 'RUN_FAIL[%s:%s]\n' "$stage" "$case_name" >&2
    cat "$runtime_stderr" >&2 || true
    return 1
  fi
  if ! cmp -s "$expected" "$runtime_stdout"; then
    printf 'OUTPUT_MISMATCH[%s:%s]\n' "$stage" "$case_name" >&2
    diff -u "$expected" "$runtime_stdout" >&2 || true
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$case_name"
}

for case_name in late_macro_proc late_macro_block_proc source_only generated_only; do
  check_stage stock "$case_name"
  check_stage candidate "$case_name"
done

printf 'PASS: source methods and generated Proc callbacks keep distinct identities\n'
