#!/usr/bin/env bash
# Stock-first no-prelude regression for inline caller frames during ivar defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -n "${ADAMAS_ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$ADAMAS_ROOT_DIR" && pwd -P)"
elif [[ -n "${ADAMAS_SAFE_RUNNER:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "$ADAMAS_SAFE_RUNNER")/.." && pwd -P)"
elif [[ -x "$SCRIPT_DIR/../scripts/run_safe.sh" ]]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
else
  ROOT_DIR="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$ROOT_DIR" ]]; then
  echo "set ADAMAS_ROOT_DIR when running this private packet outside the Adamas checkout" >&2
  exit 2
fi

SAFE_RUNNER="${ADAMAS_SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal 2>/dev/null || true)}}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/ivar_default_caller_frame"
EXPECTED_FILE="$FIXTURE_DIR/expected.stdout"
FIXTURE_HASHES="$FIXTURE_DIR/SHA256SUMS"

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
[[ -x "$SAFE_RUNNER" ]] || { echo "safe runner is unavailable: $SAFE_RUNNER" >&2; exit 2; }
[[ -n "$ORIGINAL" && -x "$ORIGINAL" ]] || {
  echo "set ORIGINAL_CRYSTAL_BIN or ORIGINAL_CRYSTAL to executable Crystal 1.22.1" >&2
  exit 2
}
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$COMPILER" ]]; then
  echo "candidate compiler is unavailable: $COMPILER" >&2
  exit 2
fi

sha256_file() {
  local path="$1"
  local line
  if command -v sha256sum >/dev/null 2>&1; then
    line="$(sha256sum "$path")" || return
  elif command -v shasum >/dev/null 2>&1; then
    line="$(shasum -a 256 "$path")" || return
  else
    echo "sha256sum or shasum is required to verify fixture bytes" >&2
    return 2
  fi
  printf '%s\n' "${line%% *}"
}

[[ -f "$EXPECTED_FILE" && -f "$FIXTURE_HASHES" ]] || {
  echo "fixture bundle is incomplete" >&2
  exit 2
}
while read -r expected_hash filename; do
  [[ -n "$expected_hash" && -n "$filename" && -f "$FIXTURE_DIR/$filename" ]] || {
    echo "invalid fixture hash manifest entry: $filename" >&2
    exit 2
  }
  actual_hash="$(sha256_file "$FIXTURE_DIR/$filename")"
  [[ "$actual_hash" == "$expected_hash" ]] || {
    echo "fixture hash mismatch: $filename" >&2
    exit 2
  }
done < "$FIXTURE_HASHES"

POSITIVE_NAMES=(
  dynamic_ivar_default_inline
  literal_ivar_default_inline
  dynamic_ivar_default_nested_proc
)

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ivar-default-caller-frame.XXXXXX")"
mkdir -p "$WORK_DIR/tmp" "$WORK_DIR/home" "$WORK_DIR/cache"
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

clean_env() {
  env -i PATH="${PATH:-/usr/bin:/bin}" HOME="$WORK_DIR/home" \
    TMPDIR="$WORK_DIR/tmp" LANG=C LC_ALL=C "$@"
}

clean_compile_env() {
  local -a link_environment=()
  [[ -n "${LIBRARY_PATH:-}" ]] && link_environment+=("LIBRARY_PATH=$LIBRARY_PATH")
  [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]] && \
    link_environment+=("ADAMAS_EXTRA_LINK_FLAGS=$ADAMAS_EXTRA_LINK_FLAGS")
  clean_env "${link_environment[@]}" "$@"
}

CRYSTAL_STDLIB="${ORIGINAL_CRYSTAL_PATH:-}"
if [[ -z "$CRYSTAL_STDLIB" ]]; then
  if ! clean_env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/crystal-env.resources" \
      "$SAFE_RUNNER" "$ORIGINAL" 20 512 env CRYSTAL_PATH \
      >"$WORK_DIR/crystal-path.out" 2>"$WORK_DIR/crystal-path.log"; then
    echo "could not read installed Crystal's CRYSTAL_PATH" >&2
    cat "$WORK_DIR/crystal-path.log" >&2
    exit 2
  fi
  CRYSTAL_STDLIB="$(tr -d '\r\n' < "$WORK_DIR/crystal-path.out")"
fi
stdlib_found=0
IFS=: read -r -a stdlib_paths <<<"$CRYSTAL_STDLIB"
for stdlib_path in "${stdlib_paths[@]}"; do
  [[ -d "$stdlib_path" ]] && stdlib_found=1
done
[[ "$stdlib_found" == 1 ]] || {
  echo "Crystal 1.22.1 CRYSTAL_PATH has no existing source directory" >&2
  exit 2
}

compile_and_run_positive() {
  local stage="$1" compiler="$2" name="$3"
  local source="$FIXTURE_DIR/$name.cr"
  local binary="$WORK_DIR/$stage-$name.bin"
  local cache="$WORK_DIR/cache/$stage-$name"
  local compile_log="$WORK_DIR/$stage-$name.compile.log"
  local stdout="$WORK_DIR/$stage-$name.stdout"
  local run_log="$WORK_DIR/$stage-$name.run.log"
  local status=0
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    local -a stock_link_flags=()
    [[ -n "${ORIGINAL_CRYSTAL_LINK_FLAGS:-}" ]] && \
      stock_link_flags=(--link-flags "$ORIGINAL_CRYSTAL_LINK_FLAGS")
    if clean_compile_env "CRYSTAL_PATH=$CRYSTAL_STDLIB" \
        "CRYSTAL_CACHE_DIR=$cache" \
        "RUN_SAFE_RESOURCE_FILE=$WORK_DIR/$stage-$name.compile.resources" \
        "$SAFE_RUNNER" "$compiler" 180 8192 build --prelude=empty \
        "${stock_link_flags[@]}" "$source" -o "$binary" --no-debug \
        >"$compile_log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if clean_compile_env "CRYSTAL_CACHE_DIR=$cache" ADAMAS_LLVM_CACHE=0 \
        "RUN_SAFE_RESOURCE_FILE=$WORK_DIR/$stage-$name.compile.resources" \
        "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-prelude \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" \
        >"$compile_log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi

  if [[ "$status" != 0 || ! -x "$binary" ]]; then
    printf 'FAIL %s positive %s (compile status %s)\n' "$stage" "$name" "$status" >&2
    cat "$compile_log" >&2
    return 1
  fi
  if ! clean_env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.run.resources" \
      "$SAFE_RUNNER" "$binary" 15 512 >"$stdout" 2>"$run_log"; then
    printf 'FAIL %s positive %s (run)\n' "$stage" "$name" >&2
    cat "$run_log" >&2
    return 1
  fi
  if ! cmp -s "$EXPECTED_FILE" "$stdout"; then
    printf 'FAIL %s positive %s (stdout bytes differ)\n' "$stage" "$name" >&2
    od -An -tx1c "$stdout" >&2
    cat "$run_log" >&2
    return 1
  fi
  printf 'PASS %s positive %s\n' "$stage" "$name"
}

# Finish the full stock baseline before compiling any candidate case.
for name in "${POSITIVE_NAMES[@]}"; do compile_and_run_positive original "$ORIGINAL" "$name"; done
if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  printf 'PASS original-only stock qualification (3 positive cases)\n'
  exit 0
fi
for name in "${POSITIVE_NAMES[@]}"; do compile_and_run_positive candidate "$COMPILER" "$name"; done
printf 'PASS ivar-default caller-frame regression (3 positive cases)\n'
