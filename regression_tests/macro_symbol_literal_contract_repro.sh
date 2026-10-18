#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FIXTURES="${MACRO_SYMBOL_FIXTURES:-$SCRIPT_DIR/macro_symbol_literal_contract}"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: %s [/path/to/adamas-or-repository-root]\n' "$0" >&2
  exit 2
fi
ROOT_HINT="${ADAMAS_ROOT:-}"
CANDIDATE_HINT="${1:-${ADAMAS_BIN:-}}"
if [[ -n "$ROOT_HINT" ]]; then
  ROOT_DIR="$(cd "$ROOT_HINT" && pwd -P)"
elif [[ -n "$CANDIDATE_HINT" && -d "$CANDIDATE_HINT" && -x "$CANDIDATE_HINT/scripts/run_safe.sh" ]]; then
  ROOT_DIR="$(cd "$CANDIDATE_HINT" && pwd -P)"
elif [[ -n "$CANDIDATE_HINT" ]]; then
  candidate_dir="$(cd "$(dirname "$CANDIDATE_HINT")" && pwd -P)"
  ROOT_DIR="$(cd "$candidate_dir/.." && pwd -P)"
else
  printf 'set ADAMAS_ROOT or pass the repository root/candidate binary\n' >&2
  exit 2
fi
CANDIDATE="${CANDIDATE_HINT:-$ROOT_DIR/bin/adamas}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ "$ORIGINAL_HINT" == */* ]]; then
  ORIGINAL="$ORIGINAL_HINT"
else
  ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"
fi
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
[[ -x "$SAFE_RUN" ]] || { printf 'missing executable: %s\n' "$SAFE_RUN" >&2; exit 2; }
if [[ -z "$ORIGINAL" || ! -x "$ORIGINAL" ]]; then
  printf 'missing original Crystal compiler: %s\n' "$ORIGINAL_HINT" >&2
  exit 2
fi
if [[ "${ONLY_ORIGINAL:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  printf 'missing candidate executable: %s\n' "$CANDIDATE" >&2
  exit 2
fi

ORIGINAL_LINK_ARGS=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
fi
RUNS_ROOT="${MACRO_SYMBOL_RUNS_ROOT:-${TMPDIR:-/tmp}/adamas_macro_symbol_literal}"
COMPILE_TIMEOUT_SEC="${MACRO_SYMBOL_COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${MACRO_SYMBOL_COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${MACRO_SYMBOL_RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${MACRO_SYMBOL_RUN_MAX_MEM_MB:-512}"
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
  if [[ -d "$ROOT_DIR/../crystal/src" ]]; then
    CRYSTAL_PATH="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
  else
    CRYSTAL_PATH_STATUS=0
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$ORIGINAL" 10 1024 env CRYSTAL_PATH \
      >"$WORK/crystal_path" 2>"$WORK/crystal_path.log" || CRYSTAL_PATH_STATUS=$?
    if [[ "$CRYSTAL_PATH_STATUS" -ne 0 ]]; then
      printf 'could not obtain CRYSTAL_PATH from original Crystal\n' >&2
      cat "$WORK/crystal_path.log" >&2 || true
      exit 2
    fi
    CRYSTAL_PATH="$(cat "$WORK/crystal_path")"
  fi
fi
if [[ -z "$CRYSTAL_PATH" || ! -d "$CRYSTAL_PATH" ]]; then
  printf 'CRYSTAL_PATH is unavailable; set it or provide a Crystal source sibling\n' >&2
  exit 2
fi
export CRYSTAL_PATH

safe_footer_ok() {
  python3 - "$1" <<'PY_SAFE_FOOTER'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None:
    raise SystemExit("missing trailing run_safe resource footer")
footer = resource.group(0)
if b"outcome=exit" not in footer or b"reason=exit" not in footer or b"exit_code=0" not in footer:
    raise SystemExit("run_safe did not record a successful exit")
without_resource = raw[:resource.start()]
if re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', without_resource) is None:
    raise SystemExit("missing successful run_safe exit footer")
PY_SAFE_FOOTER
}

runtime_stderr_is_empty() {
  python3 - "$1" <<'PY_CHECK_STDERR'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b"outcome=exit" not in resource.group(0) or b"reason=exit" not in resource.group(0) or b"exit_code=0" not in resource.group(0):
    raise SystemExit("runtime log lacks the successful run_safe resource footer")
without_resource = raw[:resource.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', without_resource)
if exit_line is None:
    raise SystemExit("runtime log contains non-wrapper stderr or lacks the successful exit footer")
if without_resource[:exit_line.start()]:
    raise SystemExit("runtime stderr is not empty after stripping run_safe metadata")
PY_CHECK_STDERR
}

compile_one() {
  local stage="$1" compiler="$2" name="$3"
  local source="$FIXTURES/$name.cr" output="$WORK/$stage.$name" log="$WORK/$stage.$name.compile.log"
  local cache="$WORK/cache.$stage.$name" status=0
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    if CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --no-debug "${ORIGINAL_LINK_ARGS[@]}" "$source" -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 || ! -x "$output" ]] || ! safe_footer_ok "$log"; then
    printf 'FAIL[%s:%s] compile status=%s or unsuccessful run_safe footer\n' "$stage" "$name" "$status" >&2
    tail -n 50 "$log" >&2 || true
    return 1
  fi
}

compile_and_run() {
  local stage="$1" compiler="$2" name="$3"
  local output="$WORK/$stage.$name" stdout="$WORK/$stage.$name.stdout" stderr="$WORK/$stage.$name.stderr"
  local status=0
  if ! compile_one "$stage" "$compiler" "$name"; then return 1; fi
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -ne 0 ]] || ! runtime_stderr_is_empty "$stderr"; then
    printf 'FAIL[%s:%s] runtime status/stderr status=%s\n' "$stage" "$name" "$status" >&2
    cat "$stderr" >&2 || true
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}

# This regression covers literal-key normalization at the HIR conversion boundary.
# The broader 3737 packet retains the independently failing CLI, lexer, and annotation cases.
CASES=(literal_tuple_declarations)
for name in "${CASES[@]}"; do
  compile_and_run original "$ORIGINAL" "$name" || FAILED=1
done
if [[ "$FAILED" -ne 0 ]]; then
  printf 'ORIGINAL_PASS_INCOMPLETE; candidate phase is blocked.\n' >&2
  exit 1
fi
for name in "${CASES[@]}"; do
  if ! cmp -s "$FIXTURES/$name.expected" "$WORK/original.$name.stdout"; then
    printf 'ORIGINAL_EXPECTATION_MISMATCH[%s]\n' "$name" >&2
    diff -u "$FIXTURES/$name.expected" "$WORK/original.$name.stdout" >&2 || true
    exit 1
  fi
done
printf 'ORIGINAL_PASS_COMPLETE cases=%d\n' "${#CASES[@]}"
if [[ "${ONLY_ORIGINAL:-0}" == 1 ]]; then exit 0; fi

FAILED=0
for name in "${CASES[@]}"; do
  compile_and_run candidate "$CANDIDATE" "$name" || FAILED=1
  if [[ -f "$WORK/candidate.$name.stdout" ]] && ! cmp -s "$WORK/original.$name.stdout" "$WORK/candidate.$name.stdout"; then
    printf 'OUTPUT_MISMATCH[%s]\n' "$name" >&2
    diff -u "$WORK/original.$name.stdout" "$WORK/candidate.$name.stdout" >&2 || true
    FAILED=1
  fi
done
if [[ "$FAILED" -ne 0 ]]; then exit 1; fi
printf 'PASS: candidate matches original on all original-qualified macro symbol literal cases.\n'
