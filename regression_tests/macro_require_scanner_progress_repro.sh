#!/usr/bin/env bash
# Require discovery must consume every macro piece/tag even on fragment recovery.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ORIGINAL="${CRYSTAL_BIN:-$(command -v crystal)}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-require-scanner-progress.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
[[ -x "$ORIGINAL" && -x "$SAFE_RUNNER" ]] || exit 2

build_args=(build "$ROOT_DIR/spec/semantic_cli_macro_require_progress_spec.cr"
  --single-module --no-debug -o "$WORK_DIR/progress_spec")
if [[ -n "${CRYSTAL_LINK_FLAGS:-}" ]]; then
  build_args+=("--link-flags=$CRYSTAL_LINK_FLAGS")
fi
if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" RUN_SAFE_RESOURCE_FILE="$WORK_DIR/build.resources" \
  "$SAFE_RUNNER" "$ORIGINAL" 180 12288 "${build_args[@]}" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
rm -rf "$WORK_DIR/cache"
if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/run.resources" \
  "$SAFE_RUNNER" "$WORK_DIR/progress_spec" 15 2048 --no-color >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
grep -Fq '7 examples, 0 failures, 0 errors' "$WORK_DIR/run.log"
printf 'PASS: macro require scanners consume fragments and preserve active branches\n'
