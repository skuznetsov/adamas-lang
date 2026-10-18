#!/usr/bin/env bash
set -euo pipefail

PACKET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FIXTURES="$PACKET_DIR/fixtures/expanded_class_ivar_defaults"
if [[ "$#" -ne 1 ]]; then
  printf 'usage: ADAMAS_ROOT=/path/to/adamas ORIGINAL_CRYSTAL_BIN=/path/to/crystal CRYSTAL_PATH=/path/to/crystal/src %s /path/to/adamas-bin\n' "$0" >&2
  exit 2
fi
CANDIDATE_HINT="$1"
CANDIDATE_DIR="$(cd "$(dirname "$CANDIDATE_HINT")" && pwd -P)"
CANDIDATE="$CANDIDATE_DIR/$(basename "$CANDIDATE_HINT")"
if [[ -n "${ADAMAS_ROOT:-}" ]]; then
  ROOT="$ADAMAS_ROOT"
elif [[ "$(basename "$CANDIDATE_DIR")" == bin ]]; then
  ROOT="$(cd "$CANDIDATE_DIR/.." && pwd -P)"
else
  printf 'set ADAMAS_ROOT when candidate is not under a repository bin/ directory\n' >&2
  exit 2
fi
SAFE_RUN="${ADAMAS_RUN_SAFE:-$ROOT/scripts/run_safe.sh}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-}"
CRYSTAL_SRC="${CRYSTAL_PATH:-}"
if [[ -z "$ORIGINAL" || -z "$CRYSTAL_SRC" ]]; then
  printf 'ORIGINAL_CRYSTAL_BIN and CRYSTAL_PATH are required\n' >&2
  exit 2
fi
for executable in "$CANDIDATE" "$ORIGINAL" "$SAFE_RUN"; do
  [[ -x "$executable" ]] || { printf 'missing executable: %s\n' "$executable" >&2; exit 2; }
done
[[ -f "$CRYSTAL_SRC/empty.cr" ]] || { printf 'missing empty prelude: %s/empty.cr\n' "$CRYSTAL_SRC" >&2; exit 2; }
export CRYSTAL_PATH="$CRYSTAL_SRC"

CASES=(generated_class_ivar_matrix generated_struct_ivar_defaults)
RUNS_ROOT="${RUNS_ROOT:-${TMPDIR:-/tmp}/adamas_expanded_class_ivar_defaults}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${RUN_MAX_MEM_MB:-512}"
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

safe_success() {
  python3 - "$1" <<'PY_SAFE_SUCCESS'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b"outcome=exit" not in resource.group(0) or b"reason=exit" not in resource.group(0) or b"exit_code=0" not in resource.group(0):
    raise SystemExit("missing successful run_safe resource footer")
if re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', raw[:resource.start()]) is None:
    raise SystemExit("missing successful run_safe exit footer")
PY_SAFE_SUCCESS
}
runtime_stderr_empty() {
  python3 - "$1" <<'PY_STDERR_EMPTY'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b"outcome=exit" not in resource.group(0) or b"reason=exit" not in resource.group(0) or b"exit_code=0" not in resource.group(0):
    raise SystemExit("runtime log lacks a successful run_safe footer")
prefix = raw[:resource.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', prefix)
if exit_line is None or prefix[:exit_line.start()]:
    raise SystemExit("runtime stderr is nonempty or wrapper footer is malformed")
PY_STDERR_EMPTY
}
compile_case() {
  local stage="$1" compiler="$2" name="$3" output="$WORK/$stage.$name.program" log="$WORK/$stage.$name.compile.log"
  local cache="$WORK/cache.$stage.$name" status=0
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    local link_args=()
    if [[ "$(uname -s)" == Darwin ]]; then link_args=(--link-flags=-fuse-ld=/usr/bin/ld); fi
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --no-debug --prelude=empty "${link_args[@]}" "$FIXTURES/$name.cr" -o "$output" >"$log" 2>&1 || status=$?
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$FIXTURES/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
  fi
  if [[ "$status" -ne 0 || ! -x "$output" ]] || ! safe_success "$log"; then
    printf 'COMPILE_FAIL[%s:%s] status=%s\n' "$stage" "$name" "$status" >&2
    tail -n 40 "$log" >&2 || true
    return 1
  fi
}
run_case() {
  local stage="$1" compiler="$2" name="$3"
  local output="$WORK/$stage.$name.program" stdout="$WORK/$stage.$name.stdout" stderr="$WORK/$stage.$name.stderr" status=0
  compile_case "$stage" "$compiler" "$name" || return 1
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr" || status=$?
  if [[ "$status" -ne 0 ]] || ! runtime_stderr_empty "$stderr" || ! cmp -s "$FIXTURES/$name.expected" "$stdout"; then
    printf 'RUN_FAIL[%s:%s] status=%s\n' "$stage" "$name" "$status" >&2
    diff -u "$FIXTURES/$name.expected" "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}

# Qualify all source expectations before invoking the Adamas candidate.
for name in "${CASES[@]}"; do run_case original "$ORIGINAL" "$name"; done
printf 'ORIGINAL_QUALIFIED cases=%d\n' "${#CASES[@]}"
for name in "${CASES[@]}"; do run_case candidate "$CANDIDATE" "$name"; done
printf 'PASS: expanded class and struct ivar storage and defaults match pinned Crystal.\n'
