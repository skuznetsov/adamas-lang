#!/usr/bin/env bash
# Preserve concrete range endpoints inside an abstract numeric restriction.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${1:-${ADAMAS_BIN:-}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_PATH="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
[[ -x "$SAFE_RUNNER" && -x "$CRYSTAL_BIN" && -d "$CRYSTAL_PATH" ]]
if [[ "$ORIGINAL_ONLY" != 1 ]]; then
  [[ -x "$ADAMAS_BIN" ]] || { echo 'pass an Adamas compiler path' >&2; exit 2; }
  ADAMAS_BIN="$(cd "$(dirname "$ADAMAS_BIN")" && pwd -P)/$(basename "$ADAMAS_BIN")"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested-numeric-range.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib RangeContractC
  fun putchar(value : Int32) : Int32
end

module WideEndpoints
  LOW = 0_u64
  HIGH = 18446744073709551615_u64
end

module RangeArgumentContract
  def self.select(value : Range(Int, Int))
    value.is_a?(Range(UInt64, UInt64)) ? 65 : 66
  end
end

RangeContractC.putchar(RangeArgumentContract.select(WideEndpoints::LOW..WideEndpoints::HIGH))
RangeContractC.putchar(RangeArgumentContract.select(0_u64..18446744073709551615_u64))
RangeContractC.putchar(10)
CRYSTAL
printf 'probe_sha256=%s\n' "$(shasum -a 256 "$WORK_DIR/probe.cr" | awk '{print $1}')"

for label in original candidate; do
  [[ "$label" != candidate || "$ORIGINAL_ONLY" != 1 ]] || continue
  prefix="$WORK_DIR/$label"
  cache="$WORK_DIR/$label.cache"
  status=0
  if [[ "$label" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$CRYSTAL_BIN" 180 8192 build "$WORK_DIR/probe.cr" \
      --no-debug --link-flags=-fuse-ld=/usr/bin/ld -o "$prefix.bin" \
      >"$prefix.build.log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 "$WORK_DIR/probe.cr" \
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$prefix.bin" \
      >"$prefix.build.log" 2>&1 || status=$?
  fi
  rm -rf "$cache"
  [[ "$status" -eq 0 ]] || { cat "$prefix.build.log" >&2; exit 1; }
  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$prefix.bin" 5 512 \
    >"$prefix.stdout" 2>"$prefix.run.log" || status=$?
  [[ "$status" -eq 0 ]] && grep -Fq '[EXIT: 0]' "$prefix.run.log" || {
    cat "$prefix.run.log" >&2; exit 1;
  }
  printf 'AA\n' >"$prefix.expected"
  diff -u "$prefix.expected" "$prefix.stdout"
done

printf 'PASS: nested numeric range specialization matches original Crystal\n'
