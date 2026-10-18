#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PACKET_DIR="$SCRIPT_DIR/source_named_argument_admission"
FIXTURE_DIR="$PACKET_DIR/fixtures"
EXPECTED_DIR="$PACKET_DIR/expected"
CANDIDATE="${1:-}"
if [[ -z "$CANDIDATE" ]]; then
  printf 'usage: %s <candidate-adamas-bin>\n' "$0" >&2
  exit 2
fi
if [[ "$CANDIDATE" != */* ]]; then CANDIDATE="$(command -v "$CANDIDATE" || true)"; fi
if [[ -z "$CANDIDATE" || ! -x "$CANDIDATE" ]]; then
  printf 'candidate compiler is not executable: %s\n' "${1:-}" >&2
  exit 2
fi

find_adamas_root() {
  local probe="$1"
  while [[ "$probe" != / ]]; do
    if [[ -x "$probe/scripts/run_safe.sh" ]]; then printf '%s\n' "$probe"; return 0; fi
    probe="$(dirname "$probe")"
  done
  return 1
}
ADAMAS_ROOT="${ADAMAS_ROOT:-}"
if [[ -z "$ADAMAS_ROOT" ]]; then
  ADAMAS_ROOT="$(find_adamas_root "$(cd "$(dirname "$CANDIDATE")" && pwd -P)")" || {
    printf 'set ADAMAS_ROOT or pass a compiler inside an Adamas checkout\n' >&2
    exit 2
  }
fi
SAFE_RUN="${SAFE_RUN:-$ADAMAS_ROOT/scripts/run_safe.sh}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
if [[ -z "$ORIGINAL" || ! -x "$ORIGINAL" || ! -x "$SAFE_RUN" ]]; then
  printf 'set ORIGINAL_CRYSTAL_BIN and ensure SAFE_RUN is executable\n' >&2
  exit 2
fi
if [[ -n "${CRYSTAL_PATH:-}" && -d "$CRYSTAL_PATH" ]]; then
  :
elif [[ -d "$ADAMAS_ROOT/../crystal/src" ]]; then
  CRYSTAL_PATH="$(cd "$ADAMAS_ROOT/../crystal/src" && pwd -P)"
else
  printf 'set CRYSTAL_PATH to the pinned Crystal source tree\n' >&2
  exit 2
fi
export CRYSTAL_PATH

RUNS_ROOT="${RUNS_ROOT:-${TMPDIR:-/tmp}/lavin3947_named_argument_admission}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${RUN_MAX_MEM_MB:-512}"
mkdir -p "$RUNS_ROOT"
RUN_DIR="$(mktemp -d "$RUNS_ROOT/run.XXXXXX")"
FAILED=0
cleanup() {
  local status=$?
  trap - EXIT
  for cache_dir in "$RUN_DIR"/cache.*; do [[ -d "$cache_dir" ]] && rm -rf -- "$cache_dir"; done
  if [[ "$status" -ne 0 || "$FAILED" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$RUN_DIR" >&2
  else
    rm -rf -- "$RUN_DIR"
  fi
  exit "$status"
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
    raise SystemExit('missing trailing run_safe resource footer')
footer = resource.group(0)
if b'outcome=exit' not in footer or b'reason=exit' not in footer or b'exit_code=0' not in footer:
    raise SystemExit('run_safe did not record successful exit')
if re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', raw[:resource.start()]) is None:
    raise SystemExit('missing successful run_safe exit footer')
PY_SAFE_FOOTER
}
compile_positive() {
  local stage="$1" compiler="$2" source="$3" binary="$4" log="$5" cache="$6" status
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --prelude=empty --no-debug --link-flags=-fuse-ld=/usr/bin/ld "$source" -o "$binary" >"$log" 2>&1 || status=$?
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || status=$?
  fi
  status="${status:-0}"
  if [[ "$status" -ne 0 || ! -x "$binary" ]] || ! safe_footer_ok "$log"; then
    printf 'COMPILE_FAILED[%s] status=%s source=%s\n' "$stage" "$status" "$source" >&2
    tail -n 45 "$log" >&2 || true
    return 1
  fi
}

compile_rejection() {
  local stage="$1" compiler="$2" source="$3" binary="$4" log="$5" cache="$6" status
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --prelude=empty --no-debug --link-flags=-fuse-ld=/usr/bin/ld "$source" -o "$binary" >"$log" 2>&1 || status=$?
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || status=$?
  fi
  status="${status:-0}"
  if [[ "$status" -ne 1 || -e "$binary" ]] || ! grep -Eiq 'no overload matches|no matching overload|expected.*Int32.*String|expected.*String.*Int32|type mismatch|argument.*Int32|restrict String to Int32' "$log"; then
    printf 'REJECTION_UNQUALIFIED[%s] status=%s executable=%s source=%s\n' "$stage" "$status" "$([[ -e "$binary" ]] && printf yes || printf no)" "$source" >&2
    tail -n 45 "$log" >&2 || true
    return 1
  fi
}

runtime_stderr_is_empty() {
  python3 - "$1" <<'PY_STDERR'
import re
import sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
footer = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if footer is None or b'outcome=exit' not in footer.group(0) or b'reason=exit' not in footer.group(0) or b'exit_code=0' not in footer.group(0):
    raise SystemExit('runtime log lacks a successful safe-run footer')
prefix = raw[:footer.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z', prefix)
if exit_line is None or prefix[:exit_line.start()]:
    raise SystemExit('runtime stderr contains a diagnostic or lacks a clean exit footer')
PY_STDERR
}

run_positive() {
  local stage case_name binary expected stdout stderr status
  stage="$1"
  case_name="$2"
  binary="$3"
  expected="$4"
  stdout="$RUN_DIR/$stage.$case_name.stdout"
  stderr="$RUN_DIR/$stage.$case_name.stderr"
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$binary" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr" || status=$?
  status="${status:-0}"
  if [[ "$status" -ne 0 ]] || ! runtime_stderr_is_empty "$stderr" || ! cmp -s "$expected" "$stdout"; then
    printf 'RUN_FAILED[%s/%s] status=%s\n' "$stage" "$case_name" "$status" >&2
    diff -u "$expected" "$stdout" >&2 || true
    tail -n 12 "$stderr" >&2 || true
    return 1
  fi
  printf 'PASS[%s/%s]\n' "$stage" "$case_name"
}

qualify() {
  local stage="$1" compiler="$2" case_name source binary log cache expected
  for case_name in explicit_new_named_default named_overload_selection named_default_evaluation_order named_constructor_factory_coexist; do
    source="$FIXTURE_DIR/$case_name.cr"
    binary="$RUN_DIR/$stage.$case_name.program"
    log="$RUN_DIR/$stage.$case_name.compile.log"
    cache="$RUN_DIR/cache.$stage.$case_name"
    expected="$EXPECTED_DIR/$case_name.stdout"
    compile_positive "$stage" "$compiler" "$source" "$binary" "$log" "$cache" || return 1
    run_positive "$stage" "$case_name" "$binary" "$expected" || return 1
  done
  for case_name in explicit_new_wrong_named_type named_wrong_type named_generic_wrong_type named_wrong_default_type named_constructor_factory_bad_type; do
    source="$FIXTURE_DIR/$case_name.cr"
    binary="$RUN_DIR/$stage.$case_name.program"
    log="$RUN_DIR/$stage.$case_name.compile.log"
    cache="$RUN_DIR/cache.$stage.$case_name"
    compile_rejection "$stage" "$compiler" "$source" "$binary" "$log" "$cache" || return 1
    printf 'PASS[%s/%s:rejected]\n' "$stage" "$case_name"
  done
}

if ! qualify original "$ORIGINAL"; then FAILED=1; exit 1; fi
printf 'ORIGINAL_QUALIFIED=1\n'
if ! qualify candidate "$CANDIDATE"; then FAILED=1; exit 1; fi
printf 'PASS: source named arguments and defaults retain type admission and evaluation order\n'
