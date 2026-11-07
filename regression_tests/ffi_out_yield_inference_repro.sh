#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/ffi_out_yield_inference"
if [[ -n "${ADAMAS_ROOT:-}" ]]; then
  ADAMAS_ROOT="$(cd "$ADAMAS_ROOT" && pwd)"
elif git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1; then
  ADAMAS_ROOT="$(git -C "$PWD" rev-parse --show-toplevel)"
else
  echo 'set ADAMAS_ROOT to the Adamas checkout containing scripts/run_safe.sh' >&2
  exit 2
fi
SAFE="${ADAMAS_RUN_SAFE:-$ADAMAS_ROOT/scripts/run_safe.sh}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
[[ -x "$SAFE" && -x "$ORIGINAL" ]] || { echo 'safe runner and original Crystal must be executable' >&2; exit 2; }
PRISTINE_CRYSTAL_PATH="${PRISTINE_CRYSTAL_PATH:-${CRYSTAL_PATH:-}}"
if [[ -z "$PRISTINE_CRYSTAL_PATH" ]]; then
  PRISTINE_CRYSTAL_PATH="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$ORIGINAL" 10 512 env CRYSTAL_PATH)"
fi
[[ -d "$PRISTINE_CRYSTAL_PATH" ]] || { echo 'set PRISTINE_CRYSTAL_PATH to the original Crystal stdlib' >&2; exit 2; }
export CRYSTAL_PATH="$PRISTINE_CRYSTAL_PATH"

case "${1:-}" in
  --original-only) [[ "$#" -eq 1 ]] || exit 2; CANDIDATE="" ;;
  --candidate) [[ "$#" -eq 2 && -n "$2" ]] || exit 2; CANDIDATE="$2" ;;
  "") CANDIDATE="${ADAMAS_BIN:-$ADAMAS_ROOT/bin/adamas}" ;;
  *) [[ "$#" -eq 1 ]] || exit 2; CANDIDATE="$1" ;;
esac
[[ -z "$CANDIDATE" || -x "$CANDIDATE" ]] || { echo "candidate is not executable: $CANDIDATE" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ffi-out-infer.XXXXXX")"
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

# Deterministic C values expose missing callback input types before lowering.
# Use private symbols so the probe does not redefine stdlib libc declarations.
"$SAFE" /usr/bin/clang 30 512 -c "$FIXTURE_DIR/helper.c" -o "$WORK/helper.o" \
  >"$WORK/helper.compile.log" 2>&1 || {
  cat "$WORK/helper.compile.log" >&2
  exit 1
}
python3 - "$FIXTURE_DIR" "$WORK" "$WORK/helper.o" <<'PY_HELPER'
from pathlib import Path
import sys
source_dir, target_dir, object_path = sys.argv[1:]
for source in Path(source_dir).glob('*.cr'):
    (Path(target_dir) / source.name).write_text(source.read_text().replace('@@FFI_YIELD_HELPER_OBJECT@@', object_path))
PY_HELPER

compile_source() {
  local stage="$1" source="$2" output="$3" log="$4"
  if [[ "$stage" == original ]]; then
    local -a args=(build "$source" --prelude=empty --no-debug -o "$output")
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
  local stage="$1" name="$2" expected_hex="$3"
  local source="$WORK/$name.cr" output="$WORK/$stage.$name.bin"
  local log="$WORK/$stage.$name.compile.log" stdout="$WORK/$stage.$name.stdout"
  local stderr="$WORK/$stage.$name.stderr" runner_log="$WORK/$stage.$name.runner.log"
  local expected="$WORK/$name.expected"
  if ! compile_source "$stage" "$source" "$output" "$log"; then
    echo "FAIL: $stage rejected positive $name" >&2; tail -60 "$log" >&2; return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 15 1024 \
    "$output" "$stderr" >"$stdout" 2>"$runner_log"; then
    echo "FAIL: $stage positive executable failed: $name" >&2; cat "$stderr" "$runner_log" >&2; return 1
  fi
  printf '%s' "$expected_hex" | xxd -r -p >"$expected"
  if ! cmp -s "$expected" "$stdout" || [[ -s "$stderr" ]]; then
    echo "FAIL: $stage output differs for $name" >&2
    od -An -tx1c "$stdout" >&2
    [[ ! -s "$stderr" ]] || cat "$stderr" >&2
    return 1
  fi
}

expect_rejection() {
  local stage="$1" name="$2" diagnostic="$3"
  local source="$WORK/$name.cr" output="$WORK/$stage.$name.bin"
  local log="$WORK/$stage.$name.compile.log" status=0
  compile_source "$stage" "$source" "$output" "$log" || status=$?
  if [[ "$status" -ne 1 || -e "$output" ]]; then
    echo "FAIL: $stage must reject $name with rc=1 and no executable, got $status" >&2
    tail -60 "$log" >&2
    return 1
  fi
  if ! grep -Fq "$diagnostic" "$log"; then
    echo "FAIL: $stage rejection lacks expected diagnostic for $name" >&2
    tail -60 "$log" >&2
    return 1
  fi
}

run_stage() {
  local stage="$1"
  run_positive "$stage" nested_struct 410a
  run_positive "$stage" named_struct 410a
  run_positive "$stage" splat_struct 410a
  run_positive "$stage" pointer_depth 430a
  expect_rejection "$stage" reject_wrong_yield_input 'Bool'
}

run_stage original
[[ -z "$CANDIDATE" ]] || run_stage candidate
echo 'PASS: original-first FFI out declaration inference through nested yields, labels, splats, and pointer depth'
