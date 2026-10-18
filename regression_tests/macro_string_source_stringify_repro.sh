#!/usr/bin/env bash
# Preserve StringLiteral source quoting through ASTNode#stringify.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURE_DIR="$ROOT_DIR/spec/fixtures/macro_string_source_stringify"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: %s [/path/to/adamas]\n' "$0" >&2
  exit 2
fi
CANDIDATE="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
if [[ -z "${CRYSTAL_PATH:-}" && -d "$ROOT_DIR/../crystal/src" ]]; then
  export CRYSTAL_PATH="$ROOT_DIR/../crystal/src"
fi
for executable in "$ORIGINAL" "$SAFE_RUN"; do
  [[ -x "$executable" ]] || { printf 'missing executable: %s\n' "$executable" >&2; exit 2; }
done
if [[ "${ONLY_ORIGINAL:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  printf 'missing candidate executable: %s\n' "$CANDIDATE" >&2
  exit 2
fi

CASES=(stringify_expression_positions stringify_macro_arguments)
RUNS_ROOT="${MACRO_RUNS_ROOT:-${TMPDIR:-/tmp}/macro-string-source-stringify}"
COMPILE_TIMEOUT_SEC="${MACRO_COMPILE_TIMEOUT_SEC:-90}"
COMPILE_MAX_MEM_MB="${MACRO_COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${MACRO_RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${MACRO_RUN_MAX_MEM_MB:-512}"
mkdir -p "$RUNS_ROOT"
WORK="$(mktemp -d "$RUNS_ROOT/run.XXXXXX")"
FAILED=0
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" -ne 0 || "$FAILED" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$ORIGINAL" 10 1024 env CRYSTAL_PATH \
    >"$WORK/crystal_path" 2>"$WORK/crystal_path.log"
  CRYSTAL_PATH="$(cat "$WORK/crystal_path")"
  [[ -n "$CRYSTAL_PATH" ]] || { printf 'empty original CRYSTAL_PATH\n' >&2; exit 2; }
  export CRYSTAL_PATH
fi
ORIGINAL_LINK_ARGS=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_ARGS+=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

compile_one() {
  local stage="$1"
  local compiler="$2"
  local name="$3"
  local source="$FIXTURE_DIR/$name.cr"
  local output="$WORK/$stage.$name"
  local log="$WORK/$stage.$name.compile.log"
  local cache="$WORK/cache.$stage.$name"
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --no-debug "${ORIGINAL_LINK_ARGS[@]}" "$source" -o "$output" >"$log" 2>&1
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1
  fi
}

runtime_stderr_is_empty() {
  local log="$1"
  python3 - "$log" <<'PY_CHECK_STDERR'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b"outcome=exit" not in resource.group(0) or b"reason=exit" not in resource.group(0) or b"exit_code=0" not in resource.group(0):
    raise SystemExit("runtime log lacks the successful run_safe footer")
without_resource = raw[:resource.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+s\n\Z', without_resource)
if exit_line is None:
    raise SystemExit("runtime log contains non-wrapper stderr or lacks the successful exit footer")
if without_resource[:exit_line.start()]:
    raise SystemExit("runtime stderr is not empty after stripping run_safe metadata")
PY_CHECK_STDERR
}

compile_and_run() {
  local stage="$1"
  local compiler="$2"
  local name="$3"
  local output="$WORK/$stage.$name"
  local compile_status=0
  compile_one "$stage" "$compiler" "$name" || compile_status=$?
  if [[ "$compile_status" -ne 0 || ! -x "$output" ]]; then
    printf 'FAIL[%s:%s] compile status=%s\n' "$stage" "$name" "$compile_status" >&2
    tail -n 40 "$WORK/$stage.$name.compile.log" >&2 || true
    return 1
  fi
  local stdout="$WORK/$stage.$name.stdout"
  local stderr="$WORK/$stage.$name.stderr"
  local run_status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr" || run_status=$?
  if [[ "$run_status" -ne 0 ]] || ! runtime_stderr_is_empty "$stderr"; then
    printf 'FAIL[%s:%s] runtime status/stderr status=%s\n' "$stage" "$name" "$run_status" >&2
    cat "$stderr" >&2 || true
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}

for name in "${CASES[@]}"; do
  compile_and_run original "$ORIGINAL" "$name" || FAILED=1
done
if [[ "$FAILED" -ne 0 ]]; then
  printf 'ORIGINAL_PASS_INCOMPLETE; candidate phase is blocked.\n' >&2
  exit 1
fi
for name in "${CASES[@]}"; do
  if ! cmp -s "$FIXTURE_DIR/$name.expected" "$WORK/original.$name.stdout"; then
    printf 'ORIGINAL_EXPECTATION_MISMATCH[%s]\n' "$name" >&2
    diff -u "$FIXTURE_DIR/$name.expected" "$WORK/original.$name.stdout" >&2 || true
    exit 1
  fi
done
printf 'ORIGINAL_PASS_COMPLETE cases=%d\n' "${#CASES[@]}"
if [[ "${ONLY_ORIGINAL:-0}" == 1 ]]; then exit 0; fi

for name in "${CASES[@]}"; do
  compile_and_run candidate "$CANDIDATE" "$name" || FAILED=1
  if [[ -f "$WORK/candidate.$name.stdout" ]] && ! cmp -s "$WORK/original.$name.stdout" "$WORK/candidate.$name.stdout"; then
    printf 'OUTPUT_MISMATCH[%s]\n' "$name" >&2
    diff -u "$WORK/original.$name.stdout" "$WORK/candidate.$name.stdout" >&2 || true
    FAILED=1
  fi
done
[[ "$FAILED" -eq 0 ]] || exit 1
printf 'PASS: candidate matches original on all original-qualified String.stringify cases.\n'
