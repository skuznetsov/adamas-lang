#!/usr/bin/env bash
# A failed complete source-family lookup must not become a guessed abort stub.
# Incomplete argument vectors retain the existing deferred resolution path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
FIXTURE_DIR="${SOURCE_FAMILY_MISS_FIXTURES:-$SCRIPT_DIR/fixtures/source_family_miss}"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: %s [/path/to/adamas]\n' "$0" >&2
  exit 2
fi
CANDIDATE="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ "$ORIGINAL_HINT" == */* ]]; then
  ORIGINAL="$ORIGINAL_HINT"
else
  ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"
fi
SAFE_RUN="${ADAMAS_RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
for executable in "$ORIGINAL" "$SAFE_RUN"; do
  [[ -n "$executable" && -x "$executable" ]] || { printf 'missing executable: %s\n' "$executable" >&2; exit 2; }
done
if [[ "${ONLY_ORIGINAL:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  printf 'missing candidate executable: %s\n' "$CANDIDATE" >&2
  exit 2
fi
RUNS_ROOT="${SOURCE_FAMILY_MISS_RUNS_ROOT:-${TMPDIR:-/tmp}/adamas_source_family_miss}"
COMPILE_TIMEOUT_SEC="${SOURCE_FAMILY_MISS_COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${SOURCE_FAMILY_MISS_COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${SOURCE_FAMILY_MISS_RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${SOURCE_FAMILY_MISS_RUN_MAX_MEM_MB:-512}"
mkdir -p "$RUNS_ROOT"
WORK="$(mktemp -d "$RUNS_ROOT/run.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then printf 'kept_artifacts=%s\n' "$WORK" >&2; else rm -rf -- "$WORK"; fi
}
trap cleanup EXIT

safe_footer_code() {
  python3 - "$1" "$2" <<'PY_FOOTER'
import re, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes(); expected = sys.argv[2].encode()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None: raise SystemExit('missing trailing run_safe resource footer')
footer = resource.group(0)
if b'outcome=exit' not in footer or b'reason=exit' not in footer or b'exit_code=' + expected not in footer: raise SystemExit('unexpected run_safe exit code')
if re.search(rb'(?m)^\[EXIT: ' + expected + rb'\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', raw[:resource.start()]) is None: raise SystemExit('missing matching exit footer')
PY_FOOTER
}
compile_program() {
  local stage compiler fixture output log cache status link_flags
  stage="$1"; compiler="$2"; fixture="$3"; output="$WORK/$stage.$fixture.program"; log="$WORK/$stage.$fixture.compile.log"; cache="$WORK/cache.$stage.$fixture"; mkdir -p "$cache"; status=0
  if [[ "$stage" == original ]]; then
    local link_args=()
    if [[ "$(uname -s)" == Darwin ]]; then link_args=(--link-flags=-fuse-ld=/usr/bin/ld); fi
    if CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug --prelude=empty "${link_args[@]}" "$FIXTURE_DIR/$fixture.cr" -o "$output" >"$log" 2>&1; then :; else status=$?; fi
  else
    link_flags=""
    if [[ "$(uname -s)" == Darwin ]]; then link_flags=-fuse-ld=/usr/bin/ld; fi
    if CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$link_flags" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" "$FIXTURE_DIR/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1; then :; else status=$?; fi
  fi
  if [[ "$status" -ne 0 || ! -x "$output" ]] || ! safe_footer_code "$log" 0; then printf 'COMPILE_FAIL[%s:%s] status=%s\n' "$stage" "$fixture" "$status" >&2; tail -n 50 "$log" >&2 || true; return 1; fi
}
run_positive() {
  local stage compiler fixture output stdout wrapper_log status
  stage="$1"; compiler="$2"; fixture="$3"; output="$WORK/$stage.$fixture.program"; stdout="$WORK/$stage.$fixture.stdout"; wrapper_log="$WORK/$stage.$fixture.run-safe.log"; status=0
  compile_program "$stage" "$compiler" "$fixture" || return 1
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$wrapper_log"; then :; else status=$?; fi
  if [[ "$status" -ne 0 ]] || ! safe_footer_code "$wrapper_log" 0; then printf 'RUN_FAIL[%s:%s] status=%s\n' "$stage" "$fixture" "$status" >&2; cat "$wrapper_log" >&2 || true; return 1; fi
  if ! cmp -s "$FIXTURE_DIR/$fixture.expected" "$stdout"; then printf 'OUTPUT_MISMATCH[%s:%s]\n' "$stage" "$fixture" >&2; diff -u "$FIXTURE_DIR/$fixture.expected" "$stdout" >&2 || true; return 1; fi
  python3 - "$wrapper_log" <<'PY_STDERR'
import re, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes(); resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None: raise SystemExit('missing resource footer')
head = raw[:resource.start()]; exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', head)
if exit_line is None or head[:exit_line.start()]: raise SystemExit('program stderr is not empty')
PY_STDERR
}
compile_negative() {
  local stage compiler fixture output log cache status
  stage="$1"; compiler="$2"; fixture="$3"; output="$WORK/$stage.$fixture.program"; log="$WORK/$stage.$fixture.compile.log"; cache="$WORK/cache.$stage.$fixture"; mkdir -p "$cache"; status=0
  if [[ "$stage" == original ]]; then
    local link_args=()
    if [[ "$(uname -s)" == Darwin ]]; then link_args=(--link-flags=-fuse-ld=/usr/bin/ld); fi
    if CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug --prelude=empty "${link_args[@]}" "$FIXTURE_DIR/$fixture.cr" -o "$output" >"$log" 2>&1; then :; else status=$?; fi
  else
    local link_flags=""
    if [[ "$(uname -s)" == Darwin ]]; then link_flags=-fuse-ld=/usr/bin/ld; fi
    if CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$link_flags" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" "$FIXTURE_DIR/$fixture.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1; then :; else status=$?; fi
  fi
  if [[ "$status" -ne 1 || -e "$output" ]] || ! safe_footer_code "$log" 1; then printf 'NEGATIVE_NOT_REJECTED[%s:%s] status=%s\n' "$stage" "$fixture" "$status" >&2; tail -n 50 "$log" >&2 || true; return 1; fi
  if ! grep -Eiq 'no overload matches|expected argument|argument.*type|type mismatch|doesn.t match|expected.*type|cannot convert' "$log"; then printf 'NEGATIVE_NOT_TYPECHECK[%s:%s]\n' "$stage" "$fixture" >&2; tail -n 50 "$log" >&2 || true; return 1; fi
}
qualify_stage() {
  local stage="$1" compiler="$2" fixture failed=0
  for fixture in overloaded_source_call_shapes no_return_argument no_return_nested_argument; do
    if ! run_positive "$stage" "$compiler" "$fixture"; then failed=1; continue; fi
    printf 'PASS[%s:%s]\n' "$stage" "$fixture"
  done
  for fixture in wrong_top_level wrong_module_method wrong_instance_method wrong_second_argument; do
    if ! compile_negative "$stage" "$compiler" "$fixture"; then failed=1; continue; fi
    printf 'PASS[%s:%s]\n' "$stage" "$fixture"
  done
  return "$failed"
}
qualify_stage original "$ORIGINAL"
printf 'ORIGINAL_PASS_COMPLETE[plain_source_family_miss]\n'
if [[ -n "$CANDIDATE" && "${ONLY_ORIGINAL:-0}" != 1 ]]; then qualify_stage candidate "$CANDIDATE"; printf 'CANDIDATE_PASS[plain_source_family_miss]\n'; fi
