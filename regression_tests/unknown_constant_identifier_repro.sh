#!/usr/bin/env bash
# Unresolved uppercase identifiers must not become implicit Void locals.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CANDIDATE="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$ROOT_DIR/../crystal/src}"
ONLY_ORIGINAL="${ONLY_ORIGINAL:-0}"
[[ -x "$SAFE_RUN" && -x "$ORIGINAL" ]] || exit 2
[[ "$ONLY_ORIGINAL" == 1 || -x "$CANDIDATE" ]] || exit 2
if [[ -z "${ADAMAS_EXTRA_LINK_FLAGS:-}" && "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld
fi
link_flags=()
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then
  link_flags+=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS")
fi
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${RUN_MAX_MEM_MB:-512}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-unknown-constant.XXXXXX")"
FIXTURE_DIR="$WORK/fixtures"
mkdir "$FIXTURE_DIR"
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

cat >"$FIXTURE_DIR/known_class.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
class Known
  def self.code
    65
  end
end
C.putchar(Known.code)
CRYSTAL
printf %s A >"$FIXTURE_DIR/known_class.expected"

cat >"$FIXTURE_DIR/lexical_constant.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
module Scope
  VALUE = 66
  def self.code
    VALUE
  end
end
C.putchar(Scope.code)
CRYSTAL
printf %s B >"$FIXTURE_DIR/lexical_constant.expected"

cat >"$FIXTURE_DIR/bound_type_parameter.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
class Marker
  def self.code
    67
  end
end
class GenericProbe(T)
  def self.code
    T.code
  end
end
C.putchar(GenericProbe(Marker).code)
CRYSTAL
printf %s C >"$FIXTURE_DIR/bound_type_parameter.expected"

cat >"$FIXTURE_DIR/builtin_metaclass.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
def consume(type : Int32.class)
  68
end
C.putchar(consume(Int32))
CRYSTAL
printf %s D >"$FIXTURE_DIR/builtin_metaclass.expected"

cat >"$FIXTURE_DIR/bare_zero_arg_method.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
def code
  69
end
C.putchar(code)
CRYSTAL
printf %s E >"$FIXTURE_DIR/bare_zero_arg_method.expected"

cat >"$FIXTURE_DIR/unknown_plain_type.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
def main
  MissingVerbatimType.new
end
main
CRYSTAL
printf '%s\n' 'undefined constant MissingVerbatimType' >"$FIXTURE_DIR/unknown_plain_type.original.reject"
printf '%s\n' 'undefined constant MissingVerbatimType' >"$FIXTURE_DIR/unknown_plain_type.candidate.reject"

cat >"$FIXTURE_DIR/unknown_bare_constant.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
def main
  MissingVerbatimType
end
main
CRYSTAL
printf '%s\n' 'undefined constant MissingVerbatimType' >"$FIXTURE_DIR/unknown_bare_constant.original.reject"
printf '%s\n' 'undefined constant MissingVerbatimType' >"$FIXTURE_DIR/unknown_bare_constant.candidate.reject"

POSITIVE_CASES=(known_class lexical_constant bound_type_parameter builtin_metaclass bare_zero_arg_method)
NEGATIVE_CASES=(unknown_plain_type unknown_bare_constant)

safe_exit_footer_ok() {
  local path="$1" expected="$2"
  python3 - "$path" "$expected" <<'PY_FOOTER'
import re, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
expected = sys.argv[2].encode()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None:
    raise SystemExit('missing trailing run_safe resource footer')
footer = resource.group(0)
if b'outcome=exit' not in footer or b'reason=exit' not in footer or b'exit_code=' + expected not in footer:
    raise SystemExit('run_safe resource footer has unexpected outcome')
prior = raw[:resource.start()]
if re.search(rb'(?m)^\[EXIT: ' + expected + rb'\] after ~[0-9]+(?:\.[0-9]+)? ?s\n?\Z', prior) is None:
    raise SystemExit('missing matching run_safe exit footer')
PY_FOOTER
}

compile_case() {
  local stage="$1" source="$2" output="$3" log="$4" cache="$5"
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$ORIGINAL" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --prelude=empty --no-debug "${link_flags[@]}" "$source" -o "$output" >"$log" 2>&1
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$CANDIDATE" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1
  fi
}

attempt_compile() {
  local stage="$1" source="$2" output="$3" log="$4" cache="$5"
  COMPILE_STATUS=0
  if compile_case "$stage" "$source" "$output" "$log" "$cache"; then
    COMPILE_STATUS=0
  else
    COMPILE_STATUS=$?
  fi
}

run_positive() {
  local stage="$1" name="$2"
  local source="$FIXTURE_DIR/$name.cr" output="$WORK/$stage.$name.program"
  local log="$WORK/$stage.$name.compile.log" cache="$WORK/cache.$stage.$name"
  local stdout="$WORK/$stage.$name.stdout" stderr="$WORK/$stage.$name.stderr"
  attempt_compile "$stage" "$source" "$output" "$log" "$cache"
  if [[ "$COMPILE_STATUS" -ne 0 || ! -x "$output" ]] || ! safe_exit_footer_ok "$log" 0; then
    printf 'COMPILE_FAIL[%s:%s] status=%s\n' "$stage" "$name" "$COMPILE_STATUS" >&2
    tail -n 40 "$log" >&2 || true
    return 1
  fi
  local run_status=0
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr"; then
    run_status=0
  else
    run_status=$?
  fi
  if [[ "$run_status" -ne 0 ]] || ! safe_exit_footer_ok "$stderr" 0 || ! python3 - "$stderr" <<'PY_STDERR'
import re, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
match = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if match is None or b'outcome=exit' not in match.group(0) or b'reason=exit' not in match.group(0) or b'exit_code=0' not in match.group(0):
    raise SystemExit('runtime stderr lacks successful run_safe resource metadata')
prior = raw[:match.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n?\Z', prior)
if exit_line is None or prior[:exit_line.start()]:
    raise SystemExit('runtime stderr contains output before the run_safe footer')
PY_STDERR
  then
    printf 'RUN_FAIL[%s:%s] status=%s\n' "$stage" "$name" "$run_status" >&2
    cat "$stderr" >&2 || true
    return 1
  fi
  if ! cmp -s "$stdout" "$FIXTURE_DIR/$name.expected"; then
    printf 'OUTPUT_MISMATCH[%s:%s] expected fixture bytes\n' "$stage" "$name" >&2
    python3 - "$stdout" "$FIXTURE_DIR/$name.expected" <<'PY_OUTPUT'
import sys
from pathlib import Path
actual = Path(sys.argv[1]).read_bytes()
expected = Path(sys.argv[2]).read_bytes()
print(f'actual={actual!r} expected={expected!r}', file=sys.stderr)
PY_OUTPUT
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}

reject_negative() {
  local stage="$1" name="$2"
  local source="$FIXTURE_DIR/$name.cr" output="$WORK/$stage.$name.program"
  local log="$WORK/$stage.$name.compile.log" cache="$WORK/cache.$stage.$name"
  rm -f -- "$output"
  attempt_compile "$stage" "$source" "$output" "$log" "$cache"
  if [[ "$COMPILE_STATUS" -ne 1 || -e "$output" ]] || ! safe_exit_footer_ok "$log" 1; then
    printf 'NEGATIVE_CONTRACT_FAIL[%s:%s] status=%s executable=%s\n' "$stage" "$name" "$COMPILE_STATUS" "$([[ -e "$output" ]] && printf yes || printf no)" >&2
    tail -n 40 "$log" >&2 || true
    return 1
  fi
  local contract="$FIXTURE_DIR/$name.$stage.reject"
  if [[ ! -f "$contract" ]]; then
    printf 'missing stage-specific rejection contract: %s\n' "$contract" >&2
    return 1
  fi
  if ! python3 - "$log" "$contract" <<'PY_REJECT'
import re, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text(errors='replace')
needles = [line.strip() for line in Path(sys.argv[2]).read_text().splitlines() if line.strip()]
missing = [needle for needle in needles if needle not in raw]
if missing:
    raise SystemExit('diagnostic is missing rejection identity fragments: ' + ', '.join(missing))
if re.search(r'(?i)(syntax error|unexpected token|expecting token|expected token|unterminated|unclosed|end of file|\beof\b)', raw):
    raise SystemExit('failure is only a parser/syntax rejection')
semantic_rejection = "undefined constant MissingVerbatimType" in raw
if not semantic_rejection:
    raise SystemExit('failure lacks the intended source semantic rejection signal')
PY_REJECT
  then
    printf 'NEGATIVE_DIAGNOSTIC_FAIL[%s:%s]\n' "$stage" "$name" >&2
    tail -n 40 "$log" >&2 || true
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}

qualify_stage() {
  local stage="$1" name failed=0
  for name in "${POSITIVE_CASES[@]}"; do run_positive "$stage" "$name" || failed=1; done
  for name in "${NEGATIVE_CASES[@]}"; do reject_negative "$stage" "$name" || failed=1; done
  return "$failed"
}

if ! qualify_stage original; then
  printf 'ORIGINAL_PASS_INCOMPLETE; candidate phase is blocked.\n' >&2
  exit 1
fi
printf 'ORIGINAL_PASS_COMPLETE positives=%d negatives=%d\n' "${#POSITIVE_CASES[@]}" "${#NEGATIVE_CASES[@]}"
if [[ "$ONLY_ORIGINAL" != 1 ]]; then
  if ! qualify_stage candidate; then
    printf 'CANDIDATE_PASS_INCOMPLETE\n' >&2
    exit 1
  fi
  printf 'CANDIDATE_PASS_COMPLETE positives=%d negatives=%d\n' "${#POSITIVE_CASES[@]}" "${#NEGATIVE_CASES[@]}"
fi
