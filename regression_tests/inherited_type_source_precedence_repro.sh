#!/usr/bin/env bash
# Original-first no-prelude checks for inherited type-source precedence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -n "${ADAMAS_ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$ADAMAS_ROOT_DIR" && pwd -P)"
elif [[ -x "$SCRIPT_DIR/../scripts/run_safe.sh" ]]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
else
  ROOT_DIR="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$ROOT_DIR" ]]; then
  echo "set ADAMAS_ROOT_DIR when running this bundle outside the Adamas checkout" >&2
  exit 2
fi

SAFE_RUNNER="${ADAMAS_SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal 2>/dev/null || true)}}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/inherited_type_source_precedence"
FIXTURE_HASHES="$FIXTURE_DIR/SHA256SUMS"

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" ]]; then
  echo "safe runner is unavailable: $SAFE_RUNNER" >&2
  exit 2
fi
if [[ -z "$ORIGINAL" || ! -x "$ORIGINAL" ]]; then
  echo "set ORIGINAL_CRYSTAL_BIN or ORIGINAL_CRYSTAL to executable Crystal 1.22.1" >&2
  exit 2
fi
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

[[ -f "$FIXTURE_HASHES" ]] || {
  echo "fixture hash manifest is missing: $FIXTURE_HASHES" >&2
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited-type-source-precedence.XXXXXX")"
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
  echo "Crystal 1.22.1 CRYSTAL_PATH has no existing source directory: $CRYSTAL_STDLIB" >&2
  exit 2
}

POSITIVE_NAMES=(
  inherited_enum_default
  inherited_alias_default
  inherited_method_restriction
  inherited_type_over_top_level
  own_alias_shadows_parent
  include_nested_type_over_unrelated_alias
)
POSITIVE_FILES=(
  inherited_enum_default.cr
  inherited_alias_default.cr
  inherited_method_restriction.cr
  inherited_type_over_top_level.cr
  own_alias_shadows_parent.cr
  include_nested_type_over_unrelated_alias.cr
)
POSITIVE_OUTPUTS=(A A A A A A)
NEGATIVE_NAME="wrong_inherited_enum_default"
NEGATIVE_FILE="wrong_inherited_enum_default.cr"

compile_positive() {
  local stage="$1"
  local compiler="$2"
  local name="$3"
  local source="$4"
  local expected="$5"
  local binary="$WORK_DIR/$stage-$name.bin"
  local cache="$WORK_DIR/cache/$stage-$name"
  local log="$WORK_DIR/$stage-$name.compile.log"
  local status=0
  local -a stock_link_flags=()
  [[ -n "${ORIGINAL_CRYSTAL_LINK_FLAGS:-}" ]] && \
    stock_link_flags=(--link-flags "$ORIGINAL_CRYSTAL_LINK_FLAGS")
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    if clean_compile_env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.compile.resources" \
        "$SAFE_RUNNER" "$compiler" 180 8192 build --prelude=empty \
        "${stock_link_flags[@]}" "$source" -o "$binary" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if clean_compile_env CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.compile.resources" \
        "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-prelude \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi

  if [[ "$status" != 0 || ! -x "$binary" ]]; then
    printf 'FAIL %s positive %s (compile status %s)\n' "$stage" "$name" "$status" >&2
    cat "$log" >&2
    return 1
  fi

  local stdout="$WORK_DIR/$stage-$name.stdout"
  local expected_file="$WORK_DIR/$stage-$name.expected"
  local run_log="$WORK_DIR/$stage-$name.run.log"
  printf '%s\n' "$expected" >"$expected_file"
  if ! clean_env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.run.resources" \
      "$SAFE_RUNNER" "$binary" 15 512 >"$stdout" 2>"$run_log"; then
    printf 'FAIL %s positive %s (run)\n' "$stage" "$name" >&2
    cat "$run_log" >&2
    return 1
  fi
  if ! cmp -s "$expected_file" "$stdout"; then
    printf 'FAIL %s positive %s (stdout bytes differ)\n' "$stage" "$name" >&2
    od -An -tx1c "$stdout" >&2
    cat "$run_log" >&2
    return 1
  fi
  printf 'PASS %s positive %s\n' "$stage" "$name"
}

compile_negative() {
  local stage="$1"
  local compiler="$2"
  local source="$3"
  local binary="$WORK_DIR/$stage-$NEGATIVE_NAME.bin"
  local cache="$WORK_DIR/cache/$stage-$NEGATIVE_NAME"
  local log="$WORK_DIR/$stage-$NEGATIVE_NAME.compile.log"
  local status=0
  local diagnostic_ok=0
  local diagnostic_count=0
  local -a stock_link_flags=()
  [[ -n "${ORIGINAL_CRYSTAL_LINK_FLAGS:-}" ]] && \
    stock_link_flags=(--link-flags "$ORIGINAL_CRYSTAL_LINK_FLAGS")
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    if clean_compile_env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$NEGATIVE_NAME.compile.resources" \
        "$SAFE_RUNNER" "$compiler" 180 8192 build --prelude=empty \
        "${stock_link_flags[@]}" "$source" -o "$binary" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
    if grep -Fq "Error: can't restrict Int32 to Type" "$log"; then
      diagnostic_ok=1
    fi
  else
    if clean_compile_env CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$NEGATIVE_NAME.compile.resources" \
        "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-prelude \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
    if grep -Fq "error: can't restrict Int32 to CarrierBase::Type" "$log"; then
      diagnostic_ok=1
    fi
  fi
  diagnostic_count="$(grep -Ec '^(error:|Error:)' "$log" || true)"

  if [[ "$status" != 1 || -e "$binary" || "$diagnostic_ok" != 1 || \
      "$diagnostic_count" != 1 ]] || \
      ! grep -Fq '[EXIT: 1]' "$log"; then
    printf 'FAIL %s negative %s (expected exit 1, no executable, and inherited enum default rejection)\n' \
      "$stage" "$NEGATIVE_NAME" >&2
    cat "$log" >&2
    return 1
  fi
  printf 'PASS %s negative %s\n' "$stage" "$NEGATIVE_NAME"
}

for index in "${!POSITIVE_NAMES[@]}"; do
  compile_positive original "$ORIGINAL" "${POSITIVE_NAMES[$index]}" \
    "$FIXTURE_DIR/${POSITIVE_FILES[$index]}" "${POSITIVE_OUTPUTS[$index]}"
done
compile_negative original "$ORIGINAL" "$FIXTURE_DIR/$NEGATIVE_FILE"

if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  printf 'PASS original-only inherited type precedence qualification (6 positives, 1 strict negative)\n'
  exit 0
fi

for index in "${!POSITIVE_NAMES[@]}"; do
  compile_positive candidate "$COMPILER" "${POSITIVE_NAMES[$index]}" \
    "$FIXTURE_DIR/${POSITIVE_FILES[$index]}" "${POSITIVE_OUTPUTS[$index]}"
done
compile_negative candidate "$COMPILER" "$FIXTURE_DIR/$NEGATIVE_FILE"
printf 'PASS inherited type-source precedence contract (6 positives, 1 strict negative)\n'
