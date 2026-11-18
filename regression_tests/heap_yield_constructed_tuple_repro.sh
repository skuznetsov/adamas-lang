#!/usr/bin/env bash
# ENV.each forwards a constructed {key, value} to ENV.keys through a captured block.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/heap-yield-constructed-tuple.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld -L/opt/homebrew/lib -lgc}"
fi

cat > "$work/keys.cr" <<'CR'
keys = ENV.keys
matches = keys.size == 2 && keys.includes?("ONE") && keys.includes?("TWO")
LibC.exit(matches ? 0 : 1)
CR

env -u CRYSTAL_PATH "$safe" "$original" 180 4096 build "$work/keys.cr" "${link[@]}" -o "$work/original"
CRYSTAL_PATH="${ADAMAS_TEST_STDLIB:-$root/src/stdlib}" "$safe" "$candidate" 240 6144 \
  "$work/keys.cr" --no-ast-cache --no-llvm-cache -o "$work/candidate"
for program in "$work/original" "$work/candidate"; do
  "$safe" /usr/bin/env 10 512 -i ONE=first TWO=second "$program"
done
echo "Both binaries recovered the two supplied environment keys"
