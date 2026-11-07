#!/usr/bin/env bash
# A depth-refused nilary member body retains an authenticated empty callshape.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="${ADAMAS_SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nilary-source-retry.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK/cache"
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT
[[ -x "$SAFE" && -x "$ORIGINAL" ]] || exit 2
LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
cd "$ROOT_DIR"
CRYSTAL_CACHE_DIR="$WORK/cache" "$SAFE" "$ORIGINAL" 180 14336 spec \
  spec/hir/staticarray_source_retry_recipe_spec.cr \
  spec/hir/required_only_arity_spec.cr \
  --single-module --no-debug "${LINK_ARGS[@]}" >"$WORK/spec.log" 2>&1 || {
  cat "$WORK/spec.log" >&2
  exit 1
}
cat "$WORK/spec.log"
printf 'PASS: nilary source retry recipe and strict arity ownership\n'
