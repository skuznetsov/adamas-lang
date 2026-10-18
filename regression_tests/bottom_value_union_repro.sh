#!/usr/bin/env bash
set -euo pipefail

PACKET_DIR="$(cd "$(dirname "$0")" && pwd -P)"
FIXTURE_DIR="$PACKET_DIR/bottom_value_union"
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
for executable in "$ORIGINAL" "$SAFE_RUN"; do
  [[ -x "$executable" ]] || { printf 'missing executable: %s\n' "$executable" >&2; exit 2; }
done
if [[ -n "$CANDIDATE" && "${ONLY_ORIGINAL:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  printf 'missing candidate executable: %s\n' "$CANDIDATE" >&2
  exit 2
fi
RUNS_ROOT="${BOTTOM_UNION_RUNS_ROOT:-${TMPDIR:-/tmp}/adamas-bottom-union-oracle}"
COMPILE_TIMEOUT_SEC="${BOTTOM_UNION_COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${BOTTOM_UNION_COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${BOTTOM_UNION_RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${BOTTOM_UNION_RUN_MAX_MEM_MB:-512}"
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
run_safe_ok() {
  python3 - "$1" <<'PY_SAFE'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b'outcome=exit' not in resource.group(0) or b'exit_code=0' not in resource.group(0):
    raise SystemExit('missing successful run_safe resource footer')
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', raw[:resource.start()])
if exit_line is None:
    raise SystemExit('missing successful run_safe exit footer')
PY_SAFE
}
runtime_stderr_empty() {
  python3 - "$1" <<'PY_STDERR'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b'exit_code=0' not in resource.group(0):
    raise SystemExit('missing successful run_safe metadata')
body = raw[:resource.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', body)
if exit_line is None or body[:exit_line.start()]:
    raise SystemExit('runtime stderr is not empty after wrapper metadata')
PY_STDERR
}
compile_one() {
  local stage="$1" compiler="$2" fixture="$3" output="$WORK/$stage.$fixture.program" log="$WORK/$stage.$fixture.compile.log" cache="$WORK/cache.$stage.$fixture" status=0
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    if [[ "$(uname -s)" == Darwin ]]; then
      CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug --prelude=empty --link-flags=-fuse-ld=/usr/bin/ld "$FIXTURE_DIR/$fixture.cr" -o "$output" >"$log" 2>&1 || status=$?
    else
      CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug --prelude=empty "$FIXTURE_DIR/$fixture.cr" -o "$output" >"$log" 2>&1 || status=$?
    fi
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" "$FIXTURE_DIR/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
  fi
  if [[ "$status" -ne 0 || ! -x "$output" ]] || ! run_safe_ok "$log"; then
    printf 'COMPILE_FAIL[%s:%s] status=%s\n' "$stage" "$fixture" "$status" >&2
    tail -n 35 "$log" >&2 || true
    return 1
  fi
}
run_positive() {
  local stage="$1" compiler="$2" fixture="$3" output="$WORK/$stage.$fixture.program" stdout="$WORK/$stage.$fixture.stdout" stderr="$WORK/$stage.$fixture.stderr" status=0
  compile_one "$stage" "$compiler" "$fixture" || return 1
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr" || status=$?
  if [[ "$status" -ne 0 ]] || ! run_safe_ok "$stderr" || ! runtime_stderr_empty "$stderr"; then
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
FIXTURE_SET="value_joins"
POSITIVE_FIXTURES=(branch_bottom alias_bottom nested_bottom all_bottom_alias)
REJECTION_FIXTURES=(ordinary_union shadow_named_bottom)
compile_rejected() {
  local stage="$1" compiler="$2" fixture="$3" output="$WORK/$stage.$fixture.program" log="$WORK/$stage.$fixture.compile.log" cache="$WORK/cache.$stage.$fixture" status=0
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    if [[ "$(uname -s)" == Darwin ]]; then
      CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug --prelude=empty --link-flags=-fuse-ld=/usr/bin/ld "$FIXTURE_DIR/$fixture.cr" -o "$output" >"$log" 2>&1 || status=$?
    else
      CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug --prelude=empty "$FIXTURE_DIR/$fixture.cr" -o "$output" >"$log" 2>&1 || status=$?
    fi
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" "$FIXTURE_DIR/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
  fi
  if [[ "$status" -ne 1 || -x "$output" ]]; then
    printf 'REJECTION_FAIL[%s:%s] status=%s executable=%s\n' "$stage" "$fixture" "$status" "$([[ -x "$output" ]] && printf yes || printf no)" >&2
    tail -n 35 "$log" >&2 || true
    return 1
  fi
  if ! python3 - "$log" "$FIXTURE_DIR/$fixture.reject" <<'PY_REJECT'
import re
import sys
from pathlib import Path
log = Path(sys.argv[1]).read_text(errors='replace')
required = [line for line in Path(sys.argv[2]).read_text().splitlines() if line]
footer = re.search(r'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*$', log)
if not footer or 'outcome=exit' not in footer.group(0) or 'exit_code=1' not in footer.group(0):
    raise SystemExit('missing ordinary compiler-error resource footer')
if re.search(r'(?i)internal compiler error|unexpected token|unexpected [A-Z][A-Za-z]+|parser errors|segmentation fault|stack overflow', log):
    raise SystemExit('rejection is not an ordinary source type diagnostic')
if not re.search(r'(?im)^Error:', log):
    raise SystemExit('compiler diagnostic is missing an Error: line')
missing = [word for word in required if word not in log]
if missing:
    raise SystemExit('rejection diagnostic is missing required type/name evidence: ' + ', '.join(missing))
PY_REJECT
  then
    printf 'REJECTION_DIAGNOSTIC_FAIL[%s:%s] status=%s\n' "$stage" "$fixture" "$status" >&2
    tail -n 35 "$log" >&2 || true
    return 1
  fi
}
qualify_stage() {
  local stage="$1" compiler="$2" fixture
  for fixture in "${POSITIVE_FIXTURES[@]}"; do
    run_positive "$stage" "$compiler" "$fixture" || return 1
    printf 'PASS[%s:%s]\n' "$stage" "$fixture"
  done
  for fixture in "${REJECTION_FIXTURES[@]}"; do
    compile_rejected "$stage" "$compiler" "$fixture" || return 1
    printf 'PASS_REJECT[%s:%s]\n' "$stage" "$fixture"
  done
}
qualify_stage original "$ORIGINAL"
printf 'ORIGINAL_PASS_COMPLETE[bottom_union:%s]\n' "$FIXTURE_SET"
if [[ -n "$CANDIDATE" && "${ONLY_ORIGINAL:-0}" != 1 ]]; then
  qualify_stage candidate "$CANDIDATE"
  printf 'CANDIDATE_PASS[bottom_union:%s]\n' "$FIXTURE_SET"
fi
