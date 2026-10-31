#!/usr/bin/env bash
# Registered structural result identities must survive factory-call repair.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/structural-result-resolution.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT
cat > "$WORK/source.cr" <<'CRYSTAL'
@[Link("c")]
lib StructuralResultOutput
  fun putchar(value : Int32) : Int32
end
class TupleResultFactory
  def self.make(value : Int32) : Tuple(Int32, UInt32)?
    {value, 1_u32}
  end
end
class NamedResultFactory
  def self.make(value : Int32) : NamedTuple(value: Int32)?
    {value: value}
  end
end
def forward_tuple(value : Int32)
  TupleResultFactory.make(value)
end
def forward_named(value : Int32)
  NamedResultFactory.make(value)
end
def observe_tuple(value : Tuple(Int32, UInt32)?) : Int32
  value ? 65 : 90
end
def observe_named(value : NamedTuple(value: Int32)?) : Int32
  value ? 66 : 90
end
StructuralResultOutput.putchar(observe_tuple(forward_tuple(7)))
StructuralResultOutput.putchar(observe_named(forward_named(9)))
StructuralResultOutput.putchar(10)
CRYSTAL
printf 'AB\n' > "$WORK/expected.stdout"
for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL" 120 4096 \
      build --prelude=empty --no-debug --link-flags="$LINK_FLAGS" \
      "$WORK/source.cr" -o "$WORK/$mode" > "$WORK/$mode.build.log" 2>&1 || {
      cat "$WORK/$mode.build.log" >&2
      exit 1
    }
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    "${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 120 4096 \
      "$WORK/source.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$WORK/$mode" > "$WORK/$mode.build.log" 2>&1 || {
      cat "$WORK/$mode.build.log" >&2
      exit 1
    }
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/$mode" 5 512 \
    > "$WORK/$mode.stdout" 2> "$WORK/$mode.run.log" || {
    cat "$WORK/$mode.run.log" >&2
    exit 1
  }
  diff -u "$WORK/expected.stdout" "$WORK/$mode.stdout"
  printf 'PASS: %s structural factory results\n' "$mode"
done
