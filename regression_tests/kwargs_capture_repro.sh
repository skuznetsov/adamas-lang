#!/usr/bin/env bash
# Original-first contract for macro **kwargs capture before the working map is cleared.
# Usage: COMPILER=/path/to/adamas ORIGINAL_CRYSTAL_BIN=/path/to/crystal \
#   CRYSTAL_PATH=/path/to/crystal/src ADAMAS_ROOT=/path/to/adamas ./kwargs_capture_repro.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
COMPILER="${1:-${COMPILER:-}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
ROOT_DIR="${ADAMAS_ROOT:-}"
if [[ -z "$ROOT_DIR" ]]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
fi
SAFE_RUNNER="${SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-$ROOT_DIR/../crystal/src}"
FIXTURE="$SCRIPT_DIR/kwargs_capture/kwargs_capture_repro.cr"
EXPECTED="$SCRIPT_DIR/kwargs_capture/expected.stdout"

if [[ -z "$COMPILER" || ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL_BIN" ||
      ! -x "$SAFE_RUNNER" || ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "ERROR: set COMPILER, ORIGINAL_CRYSTAL_BIN, and CRYSTAL_PATH (or ADAMAS_ROOT)" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-kwargs-capture.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

DEFAULT_LINK_FLAGS=""
[[ "$(uname -s)" != Darwin ]] || DEFAULT_LINK_FLAGS=-fuse-ld=/usr/bin/ld
ORIGINAL_LINK_FLAGS="${ORIGINAL_LINK_FLAGS:-${CRYSTAL_LINK_FLAGS:-$DEFAULT_LINK_FLAGS}}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-${CRYSTAL_LINK_FLAGS:-$DEFAULT_LINK_FLAGS}}"

cat >"$WORK_DIR/run_program" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
binary="$1"
stderr_file="$2"
shift 2
exec "$binary" "$@" 2>"$stderr_file"
SH
chmod +x "$WORK_DIR/run_program"

compile_original() {
  local -a args=(build "$FIXTURE" -o "$WORK_DIR/original.bin" --no-debug)
  [[ -z "$ORIGINAL_LINK_FLAGS" ]] || args+=("--link-flags=$ORIGINAL_LINK_FLAGS")
  if ! env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
    "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 "${args[@]}" \
    >"$WORK_DIR/original.compile.log" 2>&1; then
    echo "FAIL: original Crystal compilation failed" >&2
    tail -50 "$WORK_DIR/original.compile.log" >&2
    return 1
  fi
  rm -rf "$WORK_DIR/original.cache"
}

compile_candidate() {
  if ! env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" \
    ADAMAS_LLVM_CACHE=0 "$SAFE_RUNNER" "$COMPILER" 180 8192 "$FIXTURE" \
    --no-ast-cache --no-llvm-cache --no-debug --no-prelude -o "$WORK_DIR/candidate.bin" \
    >"$WORK_DIR/candidate.compile.log" 2>&1; then
    echo "FAIL: candidate compilation failed" >&2
    tail -50 "$WORK_DIR/candidate.compile.log" >&2
    return 1
  fi
  rm -rf "$WORK_DIR/candidate.cache"
}

run_and_check() {
  local stage="$1"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/run_program" 20 1024 \
    "$WORK_DIR/$stage.bin" "$WORK_DIR/$stage.stderr" \
    >"$WORK_DIR/$stage.stdout" 2>"$WORK_DIR/$stage.run.log"; then
    echo "FAIL: $stage executable failed under run_safe" >&2
    cat "$WORK_DIR/$stage.run.log" >&2
    return 1
  fi
  if [[ -s "$WORK_DIR/$stage.stderr" ]]; then
    echo "FAIL: $stage executable wrote to stderr" >&2
    cat "$WORK_DIR/$stage.stderr" >&2
    return 1
  fi
  if ! cmp -s "$EXPECTED" "$WORK_DIR/$stage.stdout"; then
    echo "FAIL: $stage stdout differs from expected macro capture bytes" >&2
    diff -u "$EXPECTED" "$WORK_DIR/$stage.stdout" >&2 || true
    return 1
  fi
}

# Establish the pinned Crystal behavior before compiling or running Adamas.
compile_original
run_and_check original

compile_candidate
run_and_check candidate
cmp "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"

echo "PASS: macro **kwargs captures empty, one, two, named-tail, and successive-call values"
