#!/usr/bin/env bash
# Cover both a white-box collision and the ordinary source path that loads
# Int#downto's `DowntoIterator(typeof(self), typeof(to))` return expression.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ORIGINAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
CANDIDATE_BIN="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"

if [[ -z "$ORIGINAL_BIN" || ! -x "$ORIGINAL_BIN" || ! -x "$SAFE_RUNNER" || ! -x "$CANDIDATE_BIN" ]]; then
  echo "ERROR: stock Crystal, candidate compiler, or safe runner is unavailable" >&2
  exit 2
fi
ORIGINAL_LINK_FLAGS=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_FLAGS=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-body-inference-owner.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/downto_typeof_owner.cr" <<'CR'
total = 0
10.downto(1).each do |value|
  total += value
end
puts total
CR

for stage in original candidate; do
  if [[ "$stage" == original ]]; then
    compiler="$ORIGINAL_BIN"
    build_args=(build "$WORK_DIR/downto_typeof_owner.cr" "${ORIGINAL_LINK_FLAGS[@]}")
  else
    compiler="$CANDIDATE_BIN"
    build_args=("$WORK_DIR/downto_typeof_owner.cr" --no-ast-cache --no-llvm-cache)
  fi
  output="$WORK_DIR/$stage-downto_typeof_owner"
  if ! ADAMAS_LLVM_CACHE=0 CRYSTAL_CACHE_DIR="$WORK_DIR/$stage-cache" \
    "$SAFE_RUNNER" "$compiler" 180 8192 "${build_args[@]}" -o "$output" \
    >"$WORK_DIR/$stage-compile.log" 2>&1; then
    cat "$WORK_DIR/$stage-compile.log" >&2
    exit 1
  fi
  if ! "$SAFE_RUNNER" "$output" 5 512 >"$WORK_DIR/$stage-run.log" 2>&1; then
    cat "$WORK_DIR/$stage-run.log" >&2
    exit 1
  fi
  if ! grep -Fxq '55' "$WORK_DIR/$stage-run.log"; then
    echo "ERROR: $stage source-path downto/typeof result differed from 55" >&2
    cat "$WORK_DIR/$stage-run.log" >&2
    exit 1
  fi
  cat "$WORK_DIR/$stage-run.log"
done
