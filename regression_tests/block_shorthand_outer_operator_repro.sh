#!/usr/bin/env bash
# Original-first regression for operators outside block shorthand calls.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${ADAMAS_ROOT:-$SCRIPT_DIR/..}" && pwd -P)"
if [[ "$#" -gt 1 ]]; then printf 'usage: %s [/path/to/adamas-bin]\n' "$0" >&2; exit 2; fi
CANDIDATE="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ "$ORIGINAL_HINT" == */* ]]; then ORIGINAL="$ORIGINAL_HINT"; else ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"; fi
SAFE_RUN="${ADAMAS_RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
[[ -x "$SAFE_RUN" && -x "$ORIGINAL" ]] || { echo 'original Crystal and run_safe.sh are required' >&2; exit 2; }
[[ "${ONLY_ORIGINAL:-0}" == 1 || -x "$CANDIDATE" ]] || { printf 'missing candidate executable: %s\n' "$CANDIDATE" >&2; exit 2; }

COMPILE_TIMEOUT_SEC="${BLOCK_SHORTHAND_COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${BLOCK_SHORTHAND_COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${BLOCK_SHORTHAND_RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${BLOCK_SHORTHAND_RUN_MAX_MEM_MB:-512}"
WORK_ROOT="${BLOCK_SHORTHAND_RUNS_ROOT:-${TMPDIR:-/tmp}/adamas_block_shorthand}"
mkdir -p "$WORK_ROOT"
WORK="$(mktemp -d "$WORK_ROOT/run.XXXXXX")"
FIXTURE_DIR="$WORK/fixtures"
mkdir -p "$FIXTURE_DIR"
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then printf 'kept_artifacts=%s\n' "$WORK" >&2; else rm -rf -- "$WORK"; fi
}
trap cleanup EXIT

if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  if [[ -d "$ROOT_DIR/../crystal/src" ]]; then
    CRYSTAL_PATH="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
  else
    path_status=0
    CRYSTAL_PATH="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$ORIGINAL" 15 1024 env CRYSTAL_PATH 2>"$WORK/crystal-path.log")" || path_status=$?
    if [[ "$path_status" -ne 0 || -z "$CRYSTAL_PATH" ]]; then echo 'could not obtain CRYSTAL_PATH; set it explicitly' >&2; cat "$WORK/crystal-path.log" >&2 || true; exit 2; fi
  fi
fi
export CRYSTAL_PATH

ORIGINAL_LINK_ARGS=()
if [[ -n "${ADAMAS_ORIGINAL_LINK_FLAGS:-}" ]]; then ORIGINAL_LINK_ARGS=("--link-flags=$ADAMAS_ORIGINAL_LINK_FLAGS")
elif [[ "$(uname -s)" == Darwin ]]; then ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld); fi

write_fixture() { local name="$1"; cat >"$FIXTURE_DIR/$name.cr"; }
write_fixture runtime_boundary <<'CR'
value : String? = nil
puts(value.try &.to_i? || 42)
value = "7"
puts(value.try &.to_i? || 42)
puts(value.try &.to_i? == 7)
puts(value.try &.to_i? != 8)
options = {"priority" => "9"}
result = {"priority": options["priority"]?.try &.to_i? || 0}
puts result[:priority]
CR
printf '42\n7\ntrue\ntrue\n9\n' >"$FIXTURE_DIR/runtime_boundary.expected"
write_fixture unary_arguments <<'CR'
struct ShorthandAdder
  def add(value : Int32)
    10 + value
  end
end
delta = 1
puts(ShorthandAdder.new.try &.add -delta)
puts(ShorthandAdder.new.try &.add +delta)
puts(ShorthandAdder.new.try &.add -1)
puts(ShorthandAdder.new.try &.add +1)
CR
printf '9\n11\n9\n11\n' >"$FIXTURE_DIR/unary_arguments.expected"
write_fixture nil_receiver_negative <<'CR'
value = nil
puts value.to_s(16)
CR

safe_exit_footer_ok() {
  python3 - "$1" "$2" <<'PY_FOOTER'
from pathlib import Path
import re, sys
raw = Path(sys.argv[1]).read_bytes()
expected = sys.argv[2].encode()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or any(x not in resource.group(0) for x in (b'outcome=exit', b'reason=exit', b'exit_code=' + expected)):
    raise SystemExit('missing or incorrect run_safe resource footer')
if re.search(rb'(?m)^\[EXIT: ' + expected + rb'\] after ~[0-9]+(?:\.[0-9]+)? ?s\n?\Z', raw[:resource.start()]) is None:
    raise SystemExit('missing matching run_safe exit footer')
PY_FOOTER
}
runtime_stderr_empty() {
  python3 - "$1" <<'PY_STDERR'
from pathlib import Path
import re, sys
raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b'exit_code=0' not in resource.group(0): raise SystemExit('missing successful run_safe footer')
prior = raw[:resource.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n?\Z', prior)
if exit_line is None or prior[:exit_line.start()]: raise SystemExit('program wrote to stderr')
PY_STDERR
}
compile_case() {
  local stage="$1" name="$2" output="$3" log="$4" cache="$5" compiler="$ORIGINAL" status=0
  [[ "$stage" == original ]] || compiler="$CANDIDATE"
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug "${ORIGINAL_LINK_ARGS[@]}" "$FIXTURE_DIR/$name.cr" -o "$output" >"$log" 2>&1 || status=$?
  else
    CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" "$FIXTURE_DIR/$name.cr" --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
  fi
  return "$status"
}
run_positive() {
  local stage="$1" name="$2" output="$WORK/$stage.$name.program" compile_log="$WORK/$stage.$name.compile.log" cache="$WORK/cache.$stage.$name" status=0
  if compile_case "$stage" "$name" "$output" "$compile_log" "$cache"; then status=0; else status=$?; fi
  if [[ "$status" -ne 0 || ! -x "$output" ]] || ! safe_exit_footer_ok "$compile_log" 0; then printf 'COMPILE_FAIL[%s:%s]\n' "$stage" "$name" >&2; tail -n 30 "$compile_log" >&2 || true; return 1; fi
  local stdout="$WORK/$stage.$name.stdout" stderr="$WORK/$stage.$name.stderr"
  status=0
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr"; then :; else status=$?; fi
  if [[ "$status" -ne 0 ]] || ! safe_exit_footer_ok "$stderr" 0 || ! runtime_stderr_empty "$stderr" || ! cmp -s "$FIXTURE_DIR/$name.expected" "$stdout"; then
    printf 'RUN_OR_OUTPUT_FAIL[%s:%s] status=%s\n' "$stage" "$name" "$status" >&2; diff -u "$FIXTURE_DIR/$name.expected" "$stdout" >&2 || true; cat "$stderr" >&2 || true; return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}
reject_negative() {
  local stage="$1" name="$2" output="$WORK/$stage.$name.program" log="$WORK/$stage.$name.compile.log" cache="$WORK/cache.$stage.$name" status=0
  rm -f -- "$output"
  if compile_case "$stage" "$name" "$output" "$log" "$cache"; then status=0; else status=$?; fi
  if [[ "$status" -ne 1 || -e "$output" ]] || ! safe_exit_footer_ok "$log" 1; then printf 'NEGATIVE_CONTRACT_FAIL[%s:%s] status=%s\n' "$stage" "$name" "$status" >&2; tail -n 30 "$log" >&2 || true; return 1; fi
  if ! python3 - "$log" <<'PY_IDENTITY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text(errors='replace')
headers = list(re.finditer(r'(?im)^(?:Error|error):', text))
if not headers: raise SystemExit('missing compiler diagnostic header')
diagnostic = '\n'.join(text[m.start():m.start() + 800] for m in headers)
if not all(token in diagnostic for token in ('to_s', 'Nil')): raise SystemExit('diagnostic does not identify Nil#to_s rejection')
if re.search(r'(?i)(undefined method|no overload|expected argument|does not match)', diagnostic) is None: raise SystemExit('diagnostic is not a method/type rejection')
PY_IDENTITY
  then printf 'NEGATIVE_DIAGNOSTIC_FAIL[%s:%s]\n' "$stage" "$name" >&2; tail -n 30 "$log" >&2 || true; return 1; fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}
qualify_stage() {
  local stage="$1" name failed=0
  for name in runtime_boundary unary_arguments; do run_positive "$stage" "$name" || failed=1; done
  reject_negative "$stage" nil_receiver_negative || failed=1
  return "$failed"
}
if ! qualify_stage original; then echo 'ORIGINAL_PASS_INCOMPLETE; candidate phase is blocked.' >&2; exit 1; fi
if [[ "${ONLY_ORIGINAL:-0}" != 1 ]]; then qualify_stage candidate; else echo 'PASS: original shorthand operator boundary contract qualified'; fi
