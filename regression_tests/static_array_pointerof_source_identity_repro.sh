#!/usr/bin/env bash
# An implicit StaticArray buffer address must retain its applied element type.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/staticarray-pointerof-source.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR/original-cache" "$WORK_DIR/candidate-cache"
  if [[ "$status" == 0 && "${KEEP_TMP:-0}" != 1 ]]; then
    rm -rf -- "$WORK_DIR"
  else
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT
[[ -x "$COMPILER" && -x "$ORIGINAL" && -x "$SAFE_RUNNER" ]]
export ADAMAS_LLVM_CACHE=0
original_link_flags="${ORIGINAL_CRYSTAL_LINK_FLAGS:-}"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
  original_link_flags="${original_link_flags:--fuse-ld=/usr/bin/ld}"
fi

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
@[Link("gc")]
struct StaticArray(T, N)
  # No annotation or typed local may conceal a lost source pointee type.
  def buffer_address
    pointerof(@buffer)
  end
end
lib PointerTagOutput
  fun putchar(value : Int32) : Int32
end
def pointer_tag(value : Pointer(UInt64)) : Int32
  65
end
def pointer_tag(value : Pointer(UInt8)) : Int32
  66
end
def pointer_tag(value : Pointer) : Int32
  88
end
words = uninitialized StaticArray(UInt64, 1)
bytes = uninitialized StaticArray(UInt8, 1)
PointerTagOutput.putchar(pointer_tag(words.buffer_address))
PointerTagOutput.putchar(pointer_tag(bytes.buffer_address))
PointerTagOutput.putchar(10)
CRYSTAL
printf 'AB\n' >"$WORK_DIR/expected.stdout"

for phase in original candidate; do
  cache="$WORK_DIR/$phase-cache"
  mkdir "$cache"
  if [[ "$phase" == original ]]; then
    args=(build --prelude=empty --no-debug --error-trace)
    [[ -z "$original_link_flags" ]] || args+=("--link-flags=$original_link_flags")
    args+=("$WORK_DIR/probe.cr")
    tool="$ORIGINAL"
  else
    args=("$WORK_DIR/probe.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    tool="$COMPILER"
  fi
  if ! CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUNNER" "$tool" 180 8192 \
      "${args[@]}" -o "$WORK_DIR/$phase" >"$WORK_DIR/$phase.build.log" 2>&1; then
    cat "$WORK_DIR/$phase.build.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$phase" 5 512 \
      >"$WORK_DIR/$phase.stdout" 2>"$WORK_DIR/$phase.run.log"; then
    cat "$WORK_DIR/$phase.run.log" >&2
    exit 1
  fi
  diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/$phase.stdout"
done
echo 'PASS: StaticArray buffer pointer types select the same overloads as Crystal'
