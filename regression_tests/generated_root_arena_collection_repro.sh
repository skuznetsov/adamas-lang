#!/usr/bin/env bash
# Generated roots retain runtime mode and their parser arena across collection.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
ORIGINAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL" && -x "$SAFE_RUNNER" && -d "$ORIGINAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generated-root-arena-collection.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

{% if true %}
  GENERATED_ROOT = 65
  def generated_root_value
    GENERATED_ROOT
  end
  LibC.putchar(generated_root_value)
{% end %}
{% begin %}
  LibC.putchar(66)
{% end %}
{% for value in %w(67 68) %}
  LibC.putchar({{value.id}})
{% end %}
LibC.putchar(69)
LibC.putchar(10)
CRYSTAL
printf 'ABCDE\n' >"$WORK_DIR/expected"

run_safe() {
  local name="$1"
  shift
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$name.resources" \
    "$SAFE_RUNNER" "$@" >"$WORK_DIR/$name.log" 2>&1; then
    cat "$WORK_DIR/$name.log" >&2
    return 1
  fi
}

run_program() {
  local name="$1"
  local binary="$2"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$name.resources" \
    "$SAFE_RUNNER" "$binary" 10 512 >"$WORK_DIR/$name.stdout" 2>"$WORK_DIR/$name.log"; then
    cat "$WORK_DIR/$name.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$name.log" || {
    cat "$WORK_DIR/$name.log" >&2
    return 1
  }
  diff -u "$WORK_DIR/expected" "$WORK_DIR/$name.stdout"
}

CRYSTAL_PATH="$ORIGINAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" run_safe original-build "$ORIGINAL" 180 8192 build "$WORK_DIR/probe.cr" \
  --error-trace --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/original"
rm -rf "$WORK_DIR/original.cache"
run_program original-run "$WORK_DIR/original"

CRYSTAL_PATH="$ORIGINAL_STDLIB" ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
  run_safe candidate-build "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" \
  --no-prelude --no-llvm-cache --no-ast-cache -o "$WORK_DIR/candidate"
run_program candidate-run "$WORK_DIR/candidate"
diff -u "$WORK_DIR/original-run.stdout" "$WORK_DIR/candidate-run.stdout"

printf 'PASS: generated parser-owned roots match original Crystal\n'
