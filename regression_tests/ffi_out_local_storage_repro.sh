#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAMAS_ROOT="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FIXTURE_DIR="$SCRIPT_DIR/ffi_out_storage"
SAFE="${ADAMAS_RUN_SAFE:-$ADAMAS_ROOT/scripts/run_safe.sh}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"

case "${1:-}" in
  --original-only)
    [[ "$#" -eq 1 ]] || { echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2; }
    CANDIDATE=""
    ;;
  --candidate)
    [[ "$#" -eq 2 && -n "$2" ]] || { echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2; }
    CANDIDATE="$2"
    ;;
  "")
    CANDIDATE="${ADAMAS_BIN:-$ADAMAS_ROOT/bin/adamas}"
    ;;
  -* )
    echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2
    exit 2
    ;;
  *)
    [[ "$#" -eq 1 ]] || { echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2; }
    CANDIDATE="$1"
    ;;
esac

PRISTINE_CRYSTAL_PATH="${PRISTINE_CRYSTAL_PATH:-${CRYSTAL_PATH:-$ADAMAS_ROOT/../crystal/src}}"
[[ -d "$PRISTINE_CRYSTAL_PATH" ]] || {
  echo 'set PRISTINE_CRYSTAL_PATH to the pinned original Crystal stdlib' >&2
  exit 2
}
export CRYSTAL_PATH="$PRISTINE_CRYSTAL_PATH"
[[ -x "$SAFE" && -x "$ORIGINAL" ]] || {
  echo 'safe runner and original Crystal must be executable' >&2
  exit 2
}
if [[ -n "$CANDIDATE" && ! -x "$CANDIDATE" ]]; then
  echo "candidate compiler is not executable: $CANDIDATE" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ffi-out-local.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

cat >"$WORK/run_program" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec "$1" 2>"$2"
SH
chmod +x "$WORK/run_program"

# Use a distinct C symbol: redefining libc pipe with Pair* is rejected by
# original Crystal because its existing declaration takes StaticArray(Int32, 2).
"$SAFE" /usr/bin/clang 30 512 -c "$FIXTURE_DIR/ffi_out_helper.c" -o "$WORK/ffi_out_helper.o" \
  >"$WORK/helper.compile.log" 2>&1 || {
  cat "$WORK/helper.compile.log" >&2
  exit 1
}
python3 - "$FIXTURE_DIR/ffi_out_lib_struct.cr" "$WORK/ffi_out_lib_struct.cr" "$WORK/ffi_out_helper.o" <<'PY_HELPER'
from pathlib import Path
import sys
source, target, object_path = sys.argv[1:]
Path(target).write_text(Path(source).read_text().replace('@@OUT_HELPER_OBJECT@@', object_path))
PY_HELPER

compile_source() {
  local stage="$1"
  local source="$2"
  local output="$3"
  local log="$4"
  if [[ "$stage" == original ]]; then
    local -a args=(build "$source" --no-debug -o "$output")
    [[ "$(uname -s)" != Darwin ]] || args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    CRYSTAL_CACHE_DIR="$WORK/original.cache" \
      "$SAFE" "$ORIGINAL" 180 8192 "${args[@]}" >"$log" 2>&1
  else
    CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE" "$CANDIDATE" 180 8192 "$source" \
      --no-ast-cache --no-llvm-cache --no-debug --no-prelude -o "$output" \
      >"$log" 2>&1
  fi
}

run_positive() {
  local stage="$1"
  local name="$2"
  local expected_text="$3"
  local source="$FIXTURE_DIR/$name.cr"
  [[ "$name" != ffi_out_lib_struct ]] || source="$WORK/ffi_out_lib_struct.cr"
  local output="$WORK/$stage.$name.bin"
  local compile_log="$WORK/$stage.$name.compile.log"
  local stdout="$WORK/$stage.$name.stdout"
  local stderr="$WORK/$stage.$name.stderr"
  local runner_log="$WORK/$stage.$name.runner.log"
  local expected="$WORK/$name.expected.stdout"

  if ! compile_source "$stage" "$source" "$output" "$compile_log"; then
    echo "FAIL: $stage rejected valid out-local fixture $name" >&2
    tail -60 "$compile_log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 15 1024 \
    "$output" "$stderr" >"$stdout" 2>"$runner_log"; then
    echo "FAIL: $stage out-local executable failed: $name" >&2
    cat "$stderr" >&2
    cat "$runner_log" >&2
    return 1
  fi
  printf '%s' "$expected_text" >"$expected"
  if ! cmp -s "$expected" "$stdout" || [[ -s "$stderr" ]]; then
    echo "FAIL: $stage output differs for $name" >&2
    od -An -tx1c "$stdout" >&2
    [[ ! -s "$stderr" ]] || cat "$stderr" >&2
    return 1
  fi
}

expect_rejection() {
  local stage="$1" name="$2"
  local output="$WORK/$stage.$name.bin" log="$WORK/$stage.$name.compile.log" status=0
  compile_source "$stage" "$FIXTURE_DIR/$name.cr" "$output" "$log" || status=$?
  if [[ "$status" -ne 1 || -e "$output" ]]; then
    echo "FAIL: $stage must reject $name with rc=1 and no executable, got $status" >&2
    tail -50 "$log" >&2
    return 1
  fi
  if ! grep -Fq 'already defined' "$log"; then
    echo "FAIL: $stage $name rejection lacks the declaration diagnostic" >&2
    tail -50 "$log" >&2
    return 1
  fi
}

run_stage() {
  local stage="$1"
  run_positive "$stage" ffi_out_pointer $'A!\nYB?\nC#\n'
  run_positive "$stage" ffi_out_primitive $'O\n'
  run_positive "$stage" captured_local_pointer $'BCY\n'
  run_positive "$stage" ffi_out_lib_struct $'P\n'
  run_positive "$stage" ffi_out_named_splat $'A!\nB!\nACC!\n'
  expect_rejection "$stage" reject_repeated
  expect_rejection "$stage" reject_preexisting
}

# Qualify the source and expected bytes on original Crystal before the candidate.
run_stage original
[[ -z "$CANDIDATE" ]] || run_stage candidate
echo 'PASS: original-first FFI out-local storage, mutation, capture, and pointer identity'
