#!/usr/bin/env bash
set -o pipefail

ROOT="${ADAMAS_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
FIXTURE_DIR="$ROOT/spec/fixtures/deferred_case_constant_dependencies"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
SAFE_RUN="${ADAMAS_RUN_SAFE:-$ROOT/scripts/run_safe.sh}"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal CRYSTAL_PATH=/path/to/crystal/src %s [/path/to/adamas]\n' "$0" >&2
  exit 2
fi
CANDIDATE="${1:-$ROOT/bin/adamas}"
if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  if [[ -d "$ROOT/../crystal/src" ]]; then
    CRYSTAL_PATH="$(cd "$ROOT/../crystal/src" && pwd -P)"
  else
    printf 'set CRYSTAL_PATH to an unmodified original Crystal stdlib\n' >&2
    exit 2
  fi
fi
export CRYSTAL_PATH
for executable in "$ORIGINAL" "$SAFE_RUN"; do
  if [[ -z "$executable" || ! -x "$executable" ]]; then
    printf 'missing executable: %s\n' "$executable" >&2
    exit 2
  fi
done
if [[ "${ONLY_ORIGINAL:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  printf 'missing candidate executable: %s\n' "$CANDIDATE" >&2
  exit 2
fi

RUNS_ROOT="${CASE_VISITOR_RUNS_ROOT:-${TMPDIR:-/tmp}/adamas_deferred_case_constants}"
COMPILE_TIMEOUT_SEC="${CASE_VISITOR_COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${CASE_VISITOR_COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${CASE_VISITOR_RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${CASE_VISITOR_RUN_MAX_MEM_MB:-512}"
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
runtime_stderr_empty() {
  python3 - "$1" <<'PY_CHECK_STDERR'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b"outcome=exit" not in resource.group(0) or b"reason=exit" not in resource.group(0) or b"exit_code=0" not in resource.group(0):
    raise SystemExit("runtime log lacks successful run_safe resource footer")
without_resource = raw[:resource.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', without_resource)
if exit_line is None or without_resource[:exit_line.start()]:
    raise SystemExit("runtime stderr is nonempty or wrapper footer is malformed")
PY_CHECK_STDERR
}

compile_run() {
  local stage="$1" compiler="$2" name=case_dependencies
  local source="$FIXTURE_DIR/$name.cr" binary="$WORK/$stage.$name" log="$WORK/$stage.$name.compile.log" cache="$WORK/cache.$stage.$name" status=0
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    local link_args=()
    if [[ "$(uname -s)" == Darwin ]]; then link_args=(--link-flags=-fuse-ld=/usr/bin/ld); fi
    if CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug "${link_args[@]}" "$source" -o "$binary" >"$log" 2>&1; then status=0; else status=$?; fi
  else
    if CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" "$source" --no-debug --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1; then status=0; else status=$?; fi
  fi
  if [[ "$status" -ne 0 || ! -x "$binary" ]] || ! safe_footer_ok "$log"; then
    printf '%s compile failed, status=%s\n' "$stage" "$status" >&2
    tail -n 40 "$log" >&2 || true
    return 1
  fi
  local kind stdout stderr expected
  for kind in empty argument; do
    local args=()
    if [[ "$kind" == argument ]]; then args=(probe); fi
    stdout="$WORK/$stage.$name.$kind.stdout"
    stderr="$WORK/$stage.$name.$kind.stderr"
    expected="$FIXTURE_DIR/$kind.expected"
    if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$binary" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" "${args[@]}" >"$stdout" 2>"$stderr"; then status=0; else status=$?; fi
    if [[ "$status" -ne 0 ]] || ! runtime_stderr_empty "$stderr"; then
      printf '%s runtime failed [%s], status=%s\n' "$stage" "$kind" "$status" >&2
      cat "$stderr" >&2 || true
      return 1
    fi
    if ! cmp -s "$expected" "$stdout"; then
      printf '%s output mismatch [%s]\n' "$stage" "$kind" >&2
      diff -u "$expected" "$stdout" >&2 || true
      return 1
    fi
  done
}

compile_run original "$ORIGINAL" || exit 1
printf 'ORIGINAL_PASS[deferred_case_constant_dependencies]\n'
if [[ -n "$CANDIDATE" && "${ONLY_ORIGINAL:-0}" != 1 ]]; then
  compile_run candidate "$CANDIDATE" || exit 1
  printf 'CANDIDATE_PASS[deferred_case_constant_dependencies]\n'
fi
