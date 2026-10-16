#!/usr/bin/env bash
# Keep byte count and lazy character count distinct in native C-string copies.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/string-cstr-metadata.XXXXXX")"
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
cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
def check(text : String)
  copy = String.new(text.to_unsafe)
  puts copy.size
  puts copy.bytesize
end
check("")
check("ASCII")
check("ж")
check("€")
check("😀")
check("жA€😀")
check("ж\0A")
check("\x80\xC0\xAF")
check("\xE0\x80\x80")
check("\xED\xA0\x80")
check("\xF4\x90\x80\x80")
check("\xF5\x80\x80\x80")
check("\xC2")
check("\xE2\x82")
check("\xF0\x9F\x98")
# Repeated reads must agree with the first lazy computation.
copy = String.new("жA€😀".to_unsafe)
puts copy.size
puts copy.size
CRYSTAL
printf '%s\n' 0 0 5 5 1 2 1 3 1 4 4 10 1 2 3 3 3 3 3 3 4 4 4 4 1 1 2 2 3 3 4 4 >"$WORK_DIR/expected.stdout"
for stage in original candidate; do
  cache="$WORK_DIR/${stage}_cache"
  mkdir "$cache"
  if [[ "$stage" == "original" ]]; then
    command=("$ORIGINAL_CRYSTAL" build "$WORK_DIR/probe.cr" --no-debug --error-trace
      --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/$stage")
  else
    command=("$COMPILER" "$WORK_DIR/probe.cr" --no-debug --no-ast-cache --no-llvm-cache
      -o "$WORK_DIR/$stage")
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
echo 'PASS: C-string copies preserve lazy UTF-8 character counts, invalid bytes and embedded-NUL boundaries'
