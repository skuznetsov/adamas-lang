#!/usr/bin/env bash
# Preserve hexadecimal f digits during AST numeric normalization.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hex-f-digit-suffix.XXXXXX")"
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
puts 0xf0
puts 0xf4
puts 0xf5
puts 0xf32
puts 0xf64
puts 0xff32
puts 0xff64
puts 0xf0f64
puts 0xF0
puts 0xf_32
puts 0xf0_i64
puts 0xf0_u64
puts 0xff32u64
puts 0b1111_u8
puts 0o17_i16
puts 42u64
puts 0xf0 + 4
CRYSTAL
printf '%s\n' 240 244 245 3890 3940 65330 65380 986980 240 3890 240 240 65330 15 15 42 244 >"$WORK_DIR/expected.stdout"
for stage in original candidate_full candidate_no_prelude; do
  cache="$WORK_DIR/${stage}_cache"
  mkdir "$cache"
  if [[ "$stage" == "original" ]]; then
    command=("$ORIGINAL_CRYSTAL" build "$WORK_DIR/probe.cr" --no-debug --error-trace
      --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/$stage")
  else
    command=("$COMPILER" "$WORK_DIR/probe.cr" --no-debug --no-ast-cache --no-llvm-cache
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
echo 'PASS: hexadecimal f digits and explicit integer suffixes match Crystal with full and no prelude'
