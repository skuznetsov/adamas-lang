#!/usr/bin/env bash
# Read nested struct fields using the same slot representation as field stores.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  export CRYSTAL_PATH="$ROOT_DIR/../crystal/src"
fi
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" ]] || exit 2
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested-struct-field-slot.XXXXXX")"
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

cat >"$WORK_DIR/pointer_child.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

struct Leaf(T)
  @value : T

  def initialize(@value : T)
  end
end

struct Wide(T)
  @leaf : Leaf(T)
  @padding : Int64

  def initialize(@leaf : Leaf(T), @padding : Int64)
  end
end

class Holder
  @wide : Wide(Int32)

  def initialize(@wide : Wide(Int32))
  end

  def read_leaf : Int32
    @wide.@leaf.@value
  end
end

holder = Holder.new(Wide(Int32).new(Leaf(Int32).new(65), 0_i64))
Probe.putchar(holder.read_leaf)
Probe.putchar(66)
CRYSTAL

cat >"$WORK_DIR/inline_child.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

struct LargeLeaf
  @value : Int32
  @padding : Int64

  def initialize(@value : Int32, @padding : Int64)
  end
end

struct Wide
  @leaf : LargeLeaf
  @padding : Int64

  def initialize(@leaf : LargeLeaf, @padding : Int64)
  end
end

class Holder
  @wide : Wide

  def initialize(@wide : Wide)
  end

  def read_leaf : Int32
    @wide.@leaf.@value
  end
end

holder = Holder.new(Wide.new(LargeLeaf.new(65, 0_i64), 0_i64))
Probe.putchar(holder.read_leaf)
Probe.putchar(66)
CRYSTAL

printf AB >"$WORK_DIR/expected.stdout"
for name in pointer_child inline_child; do
  for mode in original candidate; do
    binary="$WORK_DIR/$name.$mode.bin"
    log="$WORK_DIR/$name.$mode.compile.log"
    if [[ "$mode" == original ]]; then
      if ! env CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
        "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/$name.cr" \
        --prelude=empty --no-debug --link-flags="${CRYSTAL_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
        -o "$binary" >"$log" 2>&1; then
        tail -30 "$log" >&2
        exit 1
      fi
    else
      if ! env CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" ADAMAS_LLVM_CACHE=0 \
        ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
        "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/$name.cr" --no-prelude \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" >"$log" 2>&1; then
        tail -30 "$log" >&2
        exit 1
      fi
    fi
    log="$WORK_DIR/$name.$mode.run.log"
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 15 512 \
      >"$WORK_DIR/$name.$mode.stdout" 2>"$log"; then
      cat "$log" >&2
      exit 1
    fi
    cmp "$WORK_DIR/expected.stdout" "$WORK_DIR/$name.$mode.stdout"
    if grep -Fq '=== STDERR ===' "$log"; then
      cat "$log" >&2
      exit 1
    fi
  done
  printf 'PASS[nested-struct-field-slot:%s]: original and candidate stdout AB, stderr empty\n' "$name"
done
