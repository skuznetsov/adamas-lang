#!/usr/bin/env bash
set -euo pipefail

PACKET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FIXTURE_DIR="$PACKET_DIR/ordinary_call_boundaries"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal ADAMAS_ROOT=/path/to/adamas %s [/path/to/adamas-bin]\n' "$0" >&2
  exit 2
fi
CANDIDATE_HINT="${1:-${ADAMAS_BIN:-}}"
CANDIDATE=""
ADAMAS_ROOT="${ADAMAS_ROOT:-}"
if [[ -n "$CANDIDATE_HINT" ]]; then
  CANDIDATE_DIR="$(cd "$(dirname "$CANDIDATE_HINT")" && pwd -P)"
  CANDIDATE="$CANDIDATE_DIR/$(basename "$CANDIDATE_HINT")"
  if [[ -z "$ADAMAS_ROOT" && "$(basename "$CANDIDATE_DIR")" == bin ]]; then
    ADAMAS_ROOT="$(cd "$CANDIDATE_DIR/.." && pwd -P)"
  fi
fi
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
SAFE_RUN="${ADAMAS_RUN_SAFE:-}"
if [[ -z "$SAFE_RUN" && -n "$ADAMAS_ROOT" ]]; then SAFE_RUN="$ADAMAS_ROOT/scripts/run_safe.sh"; fi
if [[ -z "$SAFE_RUN" ]]; then
  printf 'set ADAMAS_RUN_SAFE or provide ADAMAS_ROOT\n' >&2
  exit 2
fi
if [[ -z "$ORIGINAL" || ! -x "$ORIGINAL" ]]; then
  printf 'set ORIGINAL_CRYSTAL_BIN to the pinned original compiler\n' >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUN" ]]; then
  printf 'missing safe runner: %s\n' "$SAFE_RUN" >&2
  exit 2
fi
if [[ -n "$CANDIDATE" && "${ONLY_ORIGINAL:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  printf 'missing candidate compiler: %s\n' "$CANDIDATE" >&2
  exit 2
fi

ORIGINAL_DIR="$(cd "$(dirname "$ORIGINAL")" && pwd -P)"
CRYSTAL_SRC="${ORIGINAL_CRYSTAL_SRC:-${CRYSTAL_PATH:-}}"
if [[ -z "$CRYSTAL_SRC" || ! -f "$CRYSTAL_SRC/empty.cr" ]]; then
  CRYSTAL_SRC="$(cd "$ORIGINAL_DIR/../../src" 2>/dev/null && pwd -P || true)"
fi
if [[ -z "$CRYSTAL_SRC" || ! -f "$CRYSTAL_SRC/empty.cr" ]]; then
  printf 'set ORIGINAL_CRYSTAL_SRC to the pinned Crystal src directory containing empty.cr\n' >&2
  exit 2
fi
export CRYSTAL_PATH="$CRYSTAL_SRC"
RUNS_ROOT="${CALL_BOUNDARY_RUNS_ROOT:-${TMPDIR:-/tmp}/adamas-call-boundary-oracle}"
COMPILE_TIMEOUT_SEC="${CALL_BOUNDARY_COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${CALL_BOUNDARY_COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${CALL_BOUNDARY_RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${CALL_BOUNDARY_RUN_MAX_MEM_MB:-512}"
mkdir -p "$RUNS_ROOT"
WORK="$(mktemp -d "$RUNS_ROOT/run.XXXXXX")"
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

footer_exit_ok() {
  local path="$1" expected="$2"
  python3 - "$path" "$expected" <<'PY_FOOTER'
import re, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
expected = sys.argv[2].encode()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None:
    raise SystemExit("missing trailing run_safe resource footer")
if b"outcome=exit" not in resource.group(0) or b"reason=exit" not in resource.group(0) or b"exit_code=" + expected not in resource.group(0):
    raise SystemExit("run_safe resource footer has the wrong outcome")
if re.search(rb'(?m)^\[EXIT: ' + expected + rb'\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', raw[:resource.start()]) is None:
    raise SystemExit("missing matching run_safe exit footer")
PY_FOOTER
}
runtime_stderr_empty() {
  local path="$1"
  python3 - "$path" <<'PY_STDERR'
import re, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b"outcome=exit" not in resource.group(0) or b"reason=exit" not in resource.group(0) or b"exit_code=0" not in resource.group(0):
    raise SystemExit("missing successful run_safe resource footer")
prefix = raw[:resource.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', prefix)
if exit_line is None:
    raise SystemExit("missing successful run_safe exit footer")
if prefix[:exit_line.start()]:
    raise SystemExit("program wrote to stderr")
PY_STDERR
}
compile_positive() {
  local stage="$1" fixture="$2" status=0
  local output="$WORK/$stage.$fixture.program"
  local log="$WORK/$stage.$fixture.compile.log"
  local cache="$WORK/cache.$stage.$fixture"
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    local -a link_args=()
    if [[ "$(uname -s)" == Darwin ]]; then link_args=(--link-flags=-fuse-ld=/usr/bin/ld); fi
    if CRYSTAL_CACHE_DIR="$cache" CRYSTAL_PATH="$CRYSTAL_SRC" "$SAFE_RUN" "$ORIGINAL" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --no-debug --prelude=empty "${link_args[@]}" "$FIXTURE_DIR/$fixture.cr" -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$CANDIDATE" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$FIXTURE_DIR/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 || ! -x "$output" ]] || ! footer_exit_ok "$log" 0; then
    printf 'COMPILE_FAIL[%s:%s] status=%s\n' "$stage" "$fixture" "$status" >&2
    tail -n 60 "$log" >&2 || true
    return 1
  fi
}
run_positive() {
  local stage="$1" fixture="$2" status=0
  local output="$WORK/$stage.$fixture.program"
  local stdout="$WORK/$stage.$fixture.stdout"
  local stderr="$WORK/$stage.$fixture.stderr"
  if ! compile_positive "$stage" "$fixture"; then return 1; fi
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -ne 0 ]] || ! runtime_stderr_empty "$stderr"; then
    printf 'RUN_FAIL[%s:%s] status=%s\n' "$stage" "$fixture" "$status" >&2
    cat "$stderr" >&2 || true
    return 1
  fi
  if ! cmp -s "$FIXTURE_DIR/$fixture.expected" "$stdout"; then
    printf 'OUTPUT_MISMATCH[%s:%s]\n' "$stage" "$fixture" >&2
    diff -u "$FIXTURE_DIR/$fixture.expected" "$stdout" >&2 || true
    return 1
  fi
}
compile_rejection() {
  local stage="$1" fixture="$2" status=0
  local output="$WORK/$stage.$fixture.program"
  local log="$WORK/$stage.$fixture.compile.log"
  local cache="$WORK/cache.$stage.$fixture"
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    local -a link_args=()
    if [[ "$(uname -s)" == Darwin ]]; then link_args=(--link-flags=-fuse-ld=/usr/bin/ld); fi
    if CRYSTAL_CACHE_DIR="$cache" CRYSTAL_PATH="$CRYSTAL_SRC" "$SAFE_RUN" "$ORIGINAL" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --no-debug --prelude=empty "${link_args[@]}" "$FIXTURE_DIR/$fixture.cr" -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$CANDIDATE" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$FIXTURE_DIR/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 1 || -e "$output" ]] || ! footer_exit_ok "$log" 1; then
    printf 'NEGATIVE_ACCEPTED_OR_FAILED_WRONGLY[%s:%s] status=%s executable=%s\n' "$stage" "$fixture" "$status" "$([[ -e "$output" ]] && echo yes || echo no)" >&2
    tail -n 60 "$log" >&2 || true
    return 1
  fi
  if ! rg -q '(^|: )Error:|error:' "$log" || rg -qi 'Unhandled exception|Internal compiler error|Segmentation fault|panic:' "$log"; then
    printf 'NEGATIVE_NOT_A_SOURCE_DIAGNOSTIC[%s:%s]\n' "$stage" "$fixture" >&2
    tail -n 60 "$log" >&2 || true
    return 1
  fi
  if ! rg -q 'raise' "$log" || ! rg -q 'pos' "$log" || ! rg -q 'Int32' "$log" || \
     rg -qi 'parser errors|expected a statement separator|unexpected token' "$log"; then
    printf 'NEGATIVE_MISSING_NAMED_TYPE_EVIDENCE[%s:%s]\n' "$stage" "$fixture" >&2
    tail -n 60 "$log" >&2 || true
    return 1
  fi
}
qualify_stage() {
  local stage="$1"
  local fixture
  local failed=0
  for fixture in raise_named_call raise_statement_dispatch raise_bare_dispatch raise_nested_parenthesized; do
    if ! run_positive "$stage" "$fixture"; then failed=1; continue; fi
    printf 'PASS[%s:%s]\n' "$stage" "$fixture"
  done
  if compile_rejection "$stage" raise_wrong_named_type; then
    printf 'PASS[%s:raise_wrong_named_type_rejected]\n' "$stage"
  else
    failed=1
  fi
  return "$failed"
}

if ! qualify_stage original; then exit 1; fi
printf 'ORIGINAL_PASS_COMPLETE[ordinary_call_boundaries]\n'
if [[ -n "$CANDIDATE" && "${ONLY_ORIGINAL:-0}" != 1 ]]; then
  if ! qualify_stage candidate; then exit 1; fi
  printf 'CANDIDATE_PASS[ordinary_call_boundaries]\n'
fi
