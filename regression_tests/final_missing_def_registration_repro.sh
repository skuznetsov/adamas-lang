#!/usr/bin/env bash
# Repeated repairs of the same source definitions must let HIR converge.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-final-missing.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/repro.cr" <<'CRYSTAL'
require "json"

total = 0
File.open(ARGV[0]) do |file|
  Array(Int32).from_json(file) do |value|
    total += value
  end
end
abort "wrong total" unless total == 7
CRYSTAL
printf '[3,4]\n' >"$work/input.json"

if ! "$safe" "$original" 60 4096 build "$work/repro.cr" --single-module --no-debug \
    "${stock_link[@]}" -o "$work/original" >"$work/original.log" 2>&1; then
  cat "$work/original.log" >&2
  exit 1
fi
"$safe" "$work/original" 5 512 "$work/input.json"

if ! env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO \
    "$safe" "$candidate" 100 5120 "$work/repro.cr" --no-link --emit hir \
    --no-debug --no-ast-cache --no-llvm-cache -o "$work/candidate" \
    >"$work/candidate.log" 2>&1; then
  cat "$work/candidate.log" >&2
  exit 1
fi
rg -q '^func @File\.open\$.*_block\(' "$work/candidate.hir"
rg -q '^func @Array\(Int32\)\.new\(' "$work/candidate.hir"
printf 'PASS final missing lowering after repeated Def registration (lazy HIR)\n'
