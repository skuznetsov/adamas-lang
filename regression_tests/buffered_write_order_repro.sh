#!/usr/bin/env bash
# Mixed byte/Char and String/Slice writes must share the stdlib output buffer.
# Check the original first, then compare exact stdout/stderr with the candidate.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:?usage: buffered_write_order_repro.sh CANDIDATE_COMPILER}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2
SRC="$ROOT_DIR/regression_tests/buffered_write_order.cr"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buffered_write_order.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$TMP_DIR/original.cache" "$TMP_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$TMP_DIR" >&2
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT
DEFAULT_LINK_FLAGS=""
[[ "$(uname -s)" != Darwin ]] || DEFAULT_LINK_FLAGS=-fuse-ld=/usr/bin/ld
ORIGINAL_LINK_FLAGS="${ORIGINAL_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"

# Keep the program's stderr separate from the safe runner's diagnostics.
cat >"$TMP_DIR/run_program" <<'SH'
#!/usr/bin/env bash
exec "$1" "$2" 2>"$3"
SH
chmod +x "$TMP_DIR/run_program"
printf '%s' 'payload
Abyte
abcdefgh1
no-newline:xy
tail-z!
memory="abcdefgh1\nno-newline:xy\nMend"
file="abcdefgh1\nno-newline:xy\nFend"
<' >"$TMP_DIR/expected.stdout"
head -c 9000 /dev/zero | tr '\0' x >>"$TMP_DIR/expected.stdout"
printf '%s' '>mid' >>"$TMP_DIR/expected.stdout"
head -c 8190 /dev/zero | tr '\0' y >>"$TMP_DIR/expected.stdout"
printf '%s' '|end
final-no-newline.sync-on' >>"$TMP_DIR/expected.stdout"
printf 'Err!\n' >"$TMP_DIR/expected.stderr"

for stage in original candidate; do
  bin="$TMP_DIR/$stage.bin"
  if [[ "$stage" == original ]]; then
    compile_cmd=("$ORIGINAL" build "$SRC" -o "$bin" --no-debug)
    [[ -z "$ORIGINAL_LINK_FLAGS" ]] || compile_cmd+=("--link-flags=$ORIGINAL_LINK_FLAGS")
  else
    compile_cmd=("$COMPILER" "$SRC" -o "$bin" --no-debug --no-ast-cache --no-llvm-cache)
  fi
  env "CRYSTAL_CACHE_DIR=$TMP_DIR/$stage.cache" \
    "$ROOT_DIR/scripts/run_safe.sh" "${compile_cmd[0]}" 180 8192 \
    "${compile_cmd[@]:1}" >"$TMP_DIR/$stage.compile.log" 2>&1 || {
      tail -40 "$TMP_DIR/$stage.compile.log" >&2
      exit 1
    }
  rm -rf "$TMP_DIR/$stage.cache"
  for mode in file pipe; do
    out="$TMP_DIR/$stage.$mode.stdout"
    err="$TMP_DIR/$stage.$mode.stderr"
    log="$TMP_DIR/$stage.$mode.run.log"
    if [[ "$mode" == file ]]; then
      RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" \
        "$TMP_DIR/run_program" 15 1024 "$bin" "$TMP_DIR/$stage.$mode.data" "$err" \
        >"$out" 2>"$log" || { tail -40 "$log" >&2; exit 1; }
    else
      RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" \
        "$TMP_DIR/run_program" 15 1024 "$bin" "$TMP_DIR/$stage.$mode.data" "$err" \
        2>"$log" | cat >"$out" || { tail -40 "$log" >&2; exit 1; }
    fi
    cmp "$TMP_DIR/expected.stdout" "$out"
    cmp "$TMP_DIR/expected.stderr" "$err"
    if [[ "$stage" == candidate ]]; then
      cmp "$TMP_DIR/original.$mode.stdout" "$out"
      cmp "$TMP_DIR/original.$mode.stderr" "$err"
    fi
  done
done
echo 'PASS: mixed buffered writes match Crystal stdout/stderr in file and pipe modes.'
