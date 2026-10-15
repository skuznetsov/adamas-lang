#!/usr/bin/env bash
# Ordered Crystal search roots load standard shard layouts and reject missing files.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_STDLIB:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || exit 2
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shard-require.XXXXXX")"
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
mkdir -p "$WORK_DIR/first" "$WORK_DIR/second/transport/src" \
  "$WORK_DIR/second/flat/src" "$WORK_DIR/second/namespaced/src/namespaced" \
  "$WORK_DIR/second/nested/src/reader" "$WORK_DIR/second/parts/deep" \
  "$WORK_DIR/second/empty" "$WORK_DIR/project" "$WORK_DIR/external"
printf 'module RequireTransport; def self.value; 42; end; end\n' >"$WORK_DIR/second/transport/src/transport.cr"
printf 'module RequireFlat; def self.value; 43; end; end\n' >"$WORK_DIR/second/flat/src/channel.cr"
printf 'module RequireNamespaced; def self.value; 44; end; end\n' >"$WORK_DIR/second/namespaced/src/namespaced/channel.cr"
printf 'module RequireNested; def self.value; 45; end; end\n' >"$WORK_DIR/second/nested/src/reader/reader.cr"
printf 'module RequireLocal; def self.value; 46; end; end\n' >"$WORK_DIR/project/local.cr"
printf 'puts 70\nmodule RequirePart; def self.value; 47; end; end\n' >"$WORK_DIR/second/parts/a.cr"
printf 'puts 71\nmodule RequireDeep; def self.value; 48; end; end\n' >"$WORK_DIR/second/parts/deep/a.cr"
printf 'puts 72\nmodule RequireLinked; def self.value; 49; end; end\n' >"$WORK_DIR/external/a.cr"
ln -s "$WORK_DIR/external" "$WORK_DIR/second/parts/linked"
cat >"$WORK_DIR/project/main.cr" <<'CRYSTAL'
require "transport"
require "flat/channel"
require "namespaced/channel"
require "nested/reader"
require "./local.cr"
require "parts/**"
require "empty/*"
{% if false %}
  require "missing_inactive_dependency"
{% end %}
puts RequireTransport.value
puts RequireFlat.value
puts RequireNamespaced.value
puts RequireNested.value
puts RequireLocal.value
puts RequirePart.value
puts RequireDeep.value
puts RequireLinked.value
CRYSTAL
printf '70\n71\n72\n42\n43\n44\n45\n46\n47\n48\n49\n' >"$WORK_DIR/expected.stdout"
printf 'require "missing_active_dependency"\n' >"$WORK_DIR/project/missing.cr"
SEARCH_PATH="$WORK_DIR/first:$WORK_DIR/second:$CRYSTAL_STDLIB"
for label in original candidate; do
  compiler="$COMPILER"
  args=("$WORK_DIR/project/main.cr" --no-prelude --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/$label.bin")
  missing_args=("$WORK_DIR/project/missing.cr" --no-prelude --no-ast-cache --no-llvm-cache -o "$WORK_DIR/$label.missing")
  if [[ "$label" == original ]]; then
    compiler="$ORIGINAL_CRYSTAL_BIN"
    args=(build "$WORK_DIR/project/main.cr" --no-debug --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/$label.bin")
    missing_args=(build "$WORK_DIR/project/missing.cr" --no-debug --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/$label.missing")
  fi
  status=0
  env CRYSTAL_PATH="$SEARCH_PATH" CRYSTAL_CACHE_DIR="$WORK_DIR/$label.cache" \
    ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.build.resources" \
    "$SAFE_RUNNER" "$compiler" 180 8192 "${args[@]}" >"$WORK_DIR/$label.build.log" 2>&1 || status=$?
  [[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/$label.build.log" || {
    tail -40 "$WORK_DIR/$label.build.log" >&2; exit 1;
  }
  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.run.resources" \
    "$SAFE_RUNNER" "$WORK_DIR/$label.bin" 10 512 >"$WORK_DIR/$label.stdout" 2>"$WORK_DIR/$label.run.log" || status=$?
  [[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/$label.run.log" || {
    tail -40 "$WORK_DIR/$label.run.log" >&2; exit 1;
  }
  diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/$label.stdout"
  status=0
  env CRYSTAL_PATH="$SEARCH_PATH" CRYSTAL_CACHE_DIR="$WORK_DIR/$label.cache" \
    ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.missing.resources" \
    "$SAFE_RUNNER" "$compiler" 180 8192 "${missing_args[@]}" >"$WORK_DIR/$label.missing.log" 2>&1 || status=$?
  [[ "$status" == 1 ]] && grep -Fq "can't find" "$WORK_DIR/$label.missing.log" || {
    tail -40 "$WORK_DIR/$label.missing.log" >&2; exit 1;
  }
  printf 'PASS[%s]: shard values and missing-require rejection\n' "$label"
done
printf 'PASS: ordered shard search matches original Crystal (isolated no-prelude candidate)\n'
