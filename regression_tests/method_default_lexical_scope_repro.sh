#!/usr/bin/env bash
# Method defaults use earlier formal bindings in the declaration's local scope.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
candidate="${ADAMAS_BIN:-${1:-$root/bin/adamas}}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/method-default-scope.XXXXXX")"
cleanup() {
  local rc=$?
  rm -rf -- "$work/cache-original" "$work/cache-spec"
  if [[ "$rc" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$work" >&2
  else
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1
export CRYSTAL_PATH="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld}"

cat >"$work/defaults.cr" <<'CRYSTAL'
@[Link("c")]
lib Native
  fun putchar(value : Int32) : Int32
end

class DefaultScopeBuffer
  def initialize(@bytesize : Int32)
  end

  def measure(pos = 0, length = @bytesize &- pos)
    ensure_available(pos, length)
    @bytesize &- pos
  end

  private def ensure_available(pos : Int32, length : Int32 | UInt8) : Nil
    nil
  end
end

def exercise(pos : Pointer(Int32), buffer : DefaultScopeBuffer)
  Native.putchar(buffer.measure(1, 1_u8))
  Native.putchar(buffer.measure)
end

target = 0
exercise(pointerof(target), DefaultScopeBuffer.new(66))
Native.putchar(10)
CRYSTAL

printf 'AB\n' >"$work/expected"
for mode in original lazy eager; do
  binary="$work/$mode"
  mode_env=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == original ]]; then
    compiler="$original"
    args=(build "$work/defaults.cr" --prelude=empty -o "$binary"
      "--link-flags=${ADAMAS_EXTRA_LINK_FLAGS:--L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld}")
  else
    compiler="$candidate"
    args=("$work/defaults.cr" --no-prelude --no-ast-cache --no-llvm-cache -o "$binary")
    [[ "$mode" == eager ]] && mode_env+=(ADAMAS_EAGER_MONO=1)
  fi
  CRYSTAL_CACHE_DIR="$work/cache-original" ADAMAS_LLVM_CACHE=0 \
    env "${mode_env[@]}" "$safe" "$compiler" 120 8192 "${args[@]}" \
    >"$work/$mode.build.log" 2>&1 || {
      cat "$work/$mode.build.log" >&2
      exit 1
    }
  "$safe" "$binary" 5 512 >"$work/$mode.stdout" 2>"$work/$mode.run.log"
  diff -u "$work/expected" "$work/$mode.stdout"
  [[ "$mode" == original ]] || diff -u "$work/original.stdout" "$work/$mode.stdout"
  printf 'PASS %s native default scope\n' "$mode"
done

# The unit regression forces materialization without callsite types while a
# caller's Pointer-typed pos is active. The native fixture checks the public path.
cd "$root"
env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO \
  CRYSTAL_CACHE_DIR="$work/cache-spec" "$safe" "$original" 180 12288 spec \
  spec/hir/method_default_lexical_locals_spec.cr \
  spec/hir/recovered_def_arena_falsifier_spec.cr \
  spec/hir/registered_default_owner_context_spec.cr \
  spec/hir/super_default_argument_arena_spec.cr \
  spec/hir/initializer_default_binding_spec.cr --error-trace \
  "--link-flags=${ADAMAS_EXTRA_LINK_FLAGS:--L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld}" \
  >"$work/spec.log" 2>&1 || {
    cat "$work/spec.log" >&2
    exit 1
  }
echo 'PASS registered default lexical scope and arena regressions'
