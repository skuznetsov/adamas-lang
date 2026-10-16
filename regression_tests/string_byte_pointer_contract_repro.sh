#!/usr/bin/env bash
# Check String byte identity and native copy behavior across body availability.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/string-byte-contract.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -eq 0 && "${KEEP_TMP:-0}" != "1" ]]; then
    python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$WORK_DIR"
  else
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL" ]]
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
export ADAMAS_LLVM_CACHE=0
cat >"$WORK_DIR/roundtrip.cr" <<'CRYSTAL'
first = "жA".to_unsafe
second = "жA".to_unsafe()
puts String.new(first)
puts String.new(second)
puts first[0].to_i
puts first[1].to_i
puts first[2].to_i
puts first[3].to_i
puts String.new("".to_unsafe)
puts String.new("ASCII".to_unsafe)
CRYSTAL
printf 'жA\nжA\n208\n182\n65\n0\n\nASCII\n' >"$WORK_DIR/expected.stdout"
for stage in original candidate_full candidate_no_prelude; do
  cache="$WORK_DIR/${stage}_cache"
  mkdir "$cache"
  if [[ "$stage" == "original" ]]; then
    command=("$ORIGINAL_CRYSTAL" build "$WORK_DIR/roundtrip.cr" --no-debug --error-trace
      --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/$stage")
  else
    command=("$COMPILER" "$WORK_DIR/roundtrip.cr" --no-debug --no-ast-cache --no-llvm-cache
      -o "$WORK_DIR/$stage")
    if [[ "$stage" == "candidate_no_prelude" ]]; then command+=(--no-prelude); fi
  fi
  if ! CRYSTAL_CACHE_DIR="$cache" "$RUN_SAFE" "${command[0]}" 180 8192 "${command[@]:1}" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
    cat "$WORK_DIR/$stage.build.log" >&2
    exit 1
  fi
  python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$cache"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$RUN_SAFE" "$WORK_DIR/$stage" 15 1024 \
      >"$WORK_DIR/$stage.stdout" 2>"$WORK_DIR/$stage.run.log"; then
    cat "$WORK_DIR/$stage.run.log" >&2
    exit 1
  fi
  diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/$stage.stdout"
done
cat >"$WORK_DIR/override.cr" <<'CRYSTAL'
require "primitives"
class String
  def to_unsafe : Int64
    73_i64
  end
end
struct UserByteSource
  def to_unsafe : Int64
    79_i64
  end
end
fun main(argc : Int32, argv : UInt8**) : Int32
  if "probe".to_unsafe == 73_i64 && "probe".to_unsafe() == 73_i64 &&
     UserByteSource.new.to_unsafe == 79_i64 && UserByteSource.new.to_unsafe() == 79_i64
    0
  else
    9
  end
end
CRYSTAL
for stage in original candidate; do
  cache="$WORK_DIR/${stage}_override_cache"
  mkdir "$cache"
  if [[ "$stage" == "original" ]]; then
    command=("$ORIGINAL_CRYSTAL" build "$WORK_DIR/override.cr" --prelude empty --no-debug
      --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/${stage}_override")
  else
    command=("$COMPILER" "$WORK_DIR/override.cr" --no-prelude --no-debug --no-ast-cache
      --no-llvm-cache -o "$WORK_DIR/${stage}_override")
  fi
  if ! CRYSTAL_CACHE_DIR="$cache" "$RUN_SAFE" "${command[0]}" 180 8192 "${command[@]:1}" \
      >"$WORK_DIR/$stage.override.build.log" 2>&1; then
    cat "$WORK_DIR/$stage.override.build.log" >&2
    exit 1
  fi
  python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$cache"
  if ! "$RUN_SAFE" "$WORK_DIR/${stage}_override" 15 1024 \
      >"$WORK_DIR/$stage.override.run.log" 2>&1; then
    cat "$WORK_DIR/$stage.override.run.log" >&2
    exit 1
  fi
done
echo 'PASS: UTF-8/ASCII/empty String byte roundtrips and registered source-method guards match Crystal'
