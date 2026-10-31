#!/usr/bin/env bash
# Nested eager materialization must keep each generic class's fields separate.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="${SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/eager-generic-owner.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2
ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
cat >"$WORK/main.cr" <<'CRYSTAL'
lib EagerOwnerOutput
  fun putchar(value : Int32) : Int32
end
class EagerNativeBox(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end
class EagerNativeHolder(T)
  def initialize(value : T)
    @first = EagerNativeBox(T).new(value)
    @second = EagerNativeBox(T).new(value)
    @third = EagerNativeBox(T).new(value)
  end
  def emit
    EagerOwnerOutput.putchar(@first.value)
    EagerOwnerOutput.putchar(@second.value)
    EagerOwnerOutput.putchar(@third.value)
    EagerOwnerOutput.putchar(10)
  end
end
EagerNativeHolder(Int32).new(65).emit
EagerNativeHolder(Int32).new(66).emit
CRYSTAL
printf 'AAA\nBBB\n' >"$WORK/expected"
for mode in original lazy eager; do
  mode_env=(env -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == original ]]; then
    args=("$ORIGINAL" 120 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    args=("$COMPILER" 120 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    [[ "$mode" != eager ]] || mode_env+=(ADAMAS_EAGER_MONO=1)
  fi
  if ! CRYSTAL_CACHE_DIR="$WORK/cache.$mode" "${mode_env[@]}" "$SAFE_RUNNER" \
      "${args[@]}" "$WORK/main.cr" -o "$WORK/$mode.bin" >"$WORK/$mode.compile.log" 2>&1; then
    cat "$WORK/$mode.compile.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK/$mode.bin" 5 512 \
      >"$WORK/$mode.stdout" 2>"$WORK/$mode.run.log"; then
    cat "$WORK/$mode.run.log" >&2
    exit 1
  fi
  diff -u "$WORK/expected" "$WORK/$mode.stdout"
  echo "PASS[$mode]: nested generic fields retain their owner and values"
done
