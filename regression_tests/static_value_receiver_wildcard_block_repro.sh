#!/usr/bin/env bash
# StaticArray has array storage and struct dispatch. Each inferred callback
# ABI must stay with its exact source-bound specialization.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-static-block.XXXXXX")"
cleanup() {
  rm -rf -- "$work/cache"
  if [[ "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$work" >&2
  else
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT
export CRYSTAL_PATH="$(env -u CRYSTAL_PATH "$original" env CRYSTAL_PATH)"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/positive.cr" <<'CR'
small = StaticArray[1_u16, 2_u16]
mapped_small = small.map! { |value| value &+ 1_u16 }
puts mapped_small[0]
puts mapped_small[1]

wide = StaticArray[100, 200, 300]
mapped_wide = wide.map! { |value| value &+ 4 }
puts mapped_wide[0]
puts mapped_wide[2]

again = small.map! { |value| value &+ 7_u16 }
puts again[0]
CR

cat > "$work/negative.cr" <<'CR'
values = StaticArray[1_u16, 2_u16]
values.map! { |value| "wrong element type" }
CR

compile() {
  local stage="$1" source="$2"
  if [[ "$stage" == original ]]; then
    "$safe" "$original" 150 8192 build "$work/$source.cr" --no-debug \
      "${original_flags[@]}" -o "$work/$stage.$source"
  else
    "$safe" "$candidate" 150 8192 "$work/$source.cr" --no-debug \
      --no-ast-cache --no-llvm-cache -o "$work/$stage.$source"
  fi
}

printf '2\n3\n104\n304\n9\n' > "$work/expected"
for stage in original candidate; do
  log="$work/$stage.positive.log"
  if ! compile "$stage" positive > "$log" 2>&1; then
    cat "$log" >&2
    exit 1
  fi
  "$safe" "$work/$stage.positive" 5 512 > "$work/$stage.stdout"
  diff -u "$work/expected" "$work/$stage.stdout"

  code=0
  log="$work/$stage.negative.log"
  compile "$stage" negative > "$log" 2>&1 || code=$?
  if [[ "$code" != 1 || -e "$work/$stage.negative" ]] ||
     ! rg -q 'unsafe_put.*(UInt16|String)|expected argument.*UInt16' "$log" ||
     ! rg -q 'String' "$log"; then
    cat "$log" >&2
    exit 1
  fi
  printf 'PASS %s StaticArray wildcard callback dispatch and type rejection\n' "$stage"
done
