#!/usr/bin/env bash
set -euo pipefail
ONLY_ORIGINAL="${ONLY_ORIGINAL:-0}"
export ONLY_ORIGINAL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ADAMAS_ROOT="${ADAMAS_ROOT:-}"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/enum_member_annotation"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: %s [/path/to/adamas-bin]\n' "$0" >&2
  exit 2
fi

CANDIDATE_HINT="${1:-${ADAMAS_BIN:-}}"
if [[ -n "${ADAMAS_ROOT:-}" ]]; then
  ROOT_DIR="$(cd "$ADAMAS_ROOT" && pwd -P)"
elif [[ -n "$CANDIDATE_HINT" && -d "$CANDIDATE_HINT" && -x "$CANDIDATE_HINT/scripts/run_safe.sh" ]]; then
  ROOT_DIR="$(cd "$CANDIDATE_HINT" && pwd -P)"
elif [[ -n "$CANDIDATE_HINT" ]]; then
  CANDIDATE_DIR="$(cd "$(dirname "$CANDIDATE_HINT")" && pwd -P)"
  if [[ "$(basename "$CANDIDATE_DIR")" == bin ]]; then
    ROOT_DIR="$(cd "$CANDIDATE_DIR/.." && pwd -P)"
  elif [[ -x "$CANDIDATE_DIR/scripts/run_safe.sh" ]]; then
    ROOT_DIR="$CANDIDATE_DIR"
  else
    printf 'cannot infer ADAMAS_ROOT from candidate: %s\n' "$CANDIDATE_HINT" >&2
    exit 2
  fi
else
  printf 'set ADAMAS_ROOT or pass an Adamas binary\n' >&2
  exit 2
fi

CANDIDATE="${CANDIDATE_HINT:-$ROOT_DIR/bin/adamas}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ "$ORIGINAL_HINT" == */* ]]; then
  ORIGINAL="$ORIGINAL_HINT"
else
  ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"
fi
SAFE_RUN="${ADAMAS_RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
for executable in "$SAFE_RUN" "$ORIGINAL"; do
  [[ -n "$executable" && -x "$executable" ]] || {
    printf 'missing executable: %s\n' "$executable" >&2
    exit 2
  }
done
if [[ "${ONLY_ORIGINAL:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  printf 'missing candidate executable: %s\n' "$CANDIDATE" >&2
  exit 2
fi

COMPILE_TIMEOUT_SEC="${ENUM_ANNOTATION_COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${ENUM_ANNOTATION_COMPILE_MAX_MEM_MB:-8192}"
RUN_TIMEOUT_SEC="${ENUM_ANNOTATION_RUN_TIMEOUT_SEC:-5}"
RUN_MAX_MEM_MB="${ENUM_ANNOTATION_RUN_MAX_MEM_MB:-512}"
RUNS_ROOT="${ENUM_ANNOTATION_RUNS_ROOT:-${TMPDIR:-/tmp}/adamas_enum_member_annotation}"
POSITIVE_CASES=(annotated_lib_enum flags_enum_control annotation_followed_by_method)
NEGATIVE_CASES=(annotation_missing_name dangling_annotation_at_enum_end)
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

BASE_CRYSTAL_PATH="${CRYSTAL_PATH:-}"
if [[ -z "$BASE_CRYSTAL_PATH" ]]; then
  path_status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$ORIGINAL" 10 1024 env CRYSTAL_PATH \
    >"$WORK/crystal_path" 2>"$WORK/crystal_path.log" || path_status=$?
  if [[ "$path_status" -ne 0 ]]; then
    printf 'could not obtain CRYSTAL_PATH from original Crystal\n' >&2
    cat "$WORK/crystal_path.log" >&2 || true
    exit 2
  fi
  BASE_CRYSTAL_PATH="$(cat "$WORK/crystal_path")"
fi
if [[ -z "$BASE_CRYSTAL_PATH" ]]; then
  printf 'CRYSTAL_PATH is unavailable; set it or use an original Crystal with env CRYSTAL_PATH\n' >&2
  exit 2
fi
export CRYSTAL_PATH="$BASE_CRYSTAL_PATH"

ORIGINAL_LINK_ARGS=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

safe_exit_footer_ok() {
  local path="$1" expected="$2"
  python3 - "$path" "$expected" <<'PY_FOOTER'
import re
import sys
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

runtime_stderr_empty() {
  local path="$1"
  python3 - "$path" <<'PY_STDERR'
import re
import sys
from pathlib import Path

raw = Path(sys.argv[1]).read_bytes()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
if resource is None or b'outcome=exit' not in resource.group(0) or b'reason=exit' not in resource.group(0) or b'exit_code=0' not in resource.group(0):
    raise SystemExit('runtime stderr lacks successful run_safe resource metadata')
prior = raw[:resource.start()]
exit_line = re.search(rb'(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n?\Z', prior)
if exit_line is None or prior[:exit_line.start()]:
    raise SystemExit('runtime stderr contains output before the run_safe footer')
PY_STDERR
}

compile_case() {
  local stage="$1" name="$2" source="$3" output="$4" log="$5" cache="$6"
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUN" "$ORIGINAL" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --no-debug --prelude=empty "${ORIGINAL_LINK_ARGS[@]}" "$source" -o "$output" >"$log" 2>&1
  else
    CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 "$SAFE_RUN" "$CANDIDATE" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1
  fi
}

COMPILE_STATUS=0
attempt_compile() {
  local stage="$1" source="$2" output="$3" log="$4" cache="$5"
  COMPILE_STATUS=0
  if compile_case "$stage" "$(basename "$source" .cr)" "$source" "$output" "$log" "$cache"; then
    COMPILE_STATUS=0
  else
    COMPILE_STATUS=$?
  fi
}

run_positive() {
  local stage="$1" name="$2"
  local source="$FIXTURE_DIR/$name.cr" output="$WORK/$stage.$name.program"
  local compile_log="$WORK/$stage.$name.compile.log" cache="$WORK/cache.$stage.$name"
  local stdout="$WORK/$stage.$name.stdout" stderr="$WORK/$stage.$name.stderr"
  local status=0
  attempt_compile "$stage" "$source" "$output" "$compile_log" "$cache"
  status="$COMPILE_STATUS"
  if [[ "$status" -ne 0 || ! -x "$output" ]] || ! safe_exit_footer_ok "$compile_log" 0; then
    printf 'COMPILE_FAIL[%s:%s] status=%s\n' "$stage" "$name" "$status" >&2
    tail -n 40 "$compile_log" >&2 || true
    return 1
  fi
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUN" "$output" "$RUN_TIMEOUT_SEC" "$RUN_MAX_MEM_MB" >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -ne 0 ]] || ! safe_exit_footer_ok "$stderr" 0 || ! runtime_stderr_empty "$stderr"; then
    printf 'RUN_FAIL[%s:%s] status=%s\n' "$stage" "$name" "$status" >&2
    cat "$stderr" >&2 || true
    return 1
  fi
  if ! cmp -s "$FIXTURE_DIR/$name.expected" "$stdout"; then
    printf 'OUTPUT_MISMATCH[%s:%s]\n' "$stage" "$name" >&2
    diff -u "$FIXTURE_DIR/$name.expected" "$stdout" >&2 || true
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}

reject_negative() {
  local stage="$1" name="$2"
  local source="$FIXTURE_DIR/$name.cr" output="$WORK/$stage.$name.program"
  local log="$WORK/$stage.$name.compile.log" cache="$WORK/cache.$stage.$name"
  local status=0
  rm -f -- "$output"
  attempt_compile "$stage" "$source" "$output" "$log" "$cache"
  status="$COMPILE_STATUS"
  if [[ "$status" -ne 1 || -e "$output" ]] || ! safe_exit_footer_ok "$log" 1; then
    printf 'NEGATIVE_CONTRACT_FAIL[%s:%s] status=%s executable=%s\n' "$stage" "$name" "$status" "$([[ -e "$output" ]] && printf yes || printf no)" >&2
    tail -n 40 "$log" >&2 || true
    return 1
  fi
  local reject_file="$FIXTURE_DIR/$name.$stage.reject"
  if [[ ! -f "$reject_file" ]]; then
    printf 'missing stage-specific rejection oracle: %s\n' "$reject_file" >&2
    return 1
  fi
  if ! python3 - "$log" "$reject_file" <<'PY_REJECT'
import re
import sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(errors='replace')
needles = [line.strip() for line in Path(sys.argv[2]).read_text().splitlines() if line.strip()]
missing = [needle for needle in needles if needle not in raw]
if missing:
    raise SystemExit('diagnostic is missing stage-specific rejection fragments: ' + ', '.join(missing))
if re.search(r'(?i)(syntax|unexpected|expecting|expected|unterminated|unclosed|end of|eof)', raw) is None:
    raise SystemExit('failure is not a parser rejection')
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
  for name in "${POSITIVE_CASES[@]}"; do
    run_positive "$stage" "$name" || failed=1
  done
  for name in "${NEGATIVE_CASES[@]}"; do
    reject_negative "$stage" "$name" || failed=1
  done
  return "$failed"
}

if ! qualify_stage original original; then
  printf 'ORIGINAL_PASS_INCOMPLETE; candidate phase is blocked.\n' >&2
  exit 1
fi
printf 'ORIGINAL_PASS_COMPLETE positives=%d negatives=%d\n' "${#POSITIVE_CASES[@]}" "${#NEGATIVE_CASES[@]}"
if [[ "${ONLY_ORIGINAL:-0}" != 1 ]]; then
  if ! qualify_stage candidate candidate; then
    printf 'CANDIDATE_PASS_INCOMPLETE\n' >&2
    exit 1
  fi
  printf 'CANDIDATE_PASS_COMPLETE positives=%d negatives=%d\n' "${#POSITIVE_CASES[@]}" "${#NEGATIVE_CASES[@]}"
fi
