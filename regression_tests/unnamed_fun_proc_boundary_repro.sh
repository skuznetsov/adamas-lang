#!/usr/bin/env bash
# Compare original and Adamas parser boundaries, then run neighboring parser specs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SAFE_RUN="${SAFE_RUN:-$ROOT/scripts/run_safe.sh}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
if [[ ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -x "$SAFE_RUN" ]]; then
  printf 'error: set ORIGINAL_CRYSTAL_BIN and use an Adamas checkout with run_safe.sh\n' >&2
  exit 2
fi
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/unnamed_fun_proc_boundary.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$RUN_DIR/cache.original" "$RUN_DIR/cache.candidate"
  if [[ "$status" == 0 ]]; then rm -rf -- "$RUN_DIR"; else printf 'kept_artifacts=%s\n' "$RUN_DIR" >&2; fi
  exit "$status"
}
trap cleanup EXIT
link_args=()
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then link_args+=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS"); fi
CRYSTAL_CACHE_DIR="$RUN_DIR/cache.original" "$SAFE_RUN" "$ORIGINAL_CRYSTAL_BIN" 180 4096 \
  spec "$ROOT/spec/parser/parser_fun_unnamed_proc_original_spec.cr" --no-debug "${link_args[@]}"
printf 'ORIGINAL_QUALIFIED=1\n'
CRYSTAL_CACHE_DIR="$RUN_DIR/cache.candidate" "$SAFE_RUN" "$ORIGINAL_CRYSTAL_BIN" 180 4096 \
  spec "$ROOT/spec/parser/parser_fun_unnamed_proc_spec.cr" \
       "$ROOT/spec/parser/parser_fun_spec.cr" \
       "$ROOT/spec/parser/parser_proc_literal_spec.cr" \
       "$ROOT/spec/parser/parser_annotation_spec.cr" --no-debug "${link_args[@]}"
printf 'PASS: C callback formal and following-declaration boundaries match original grammar.\n'
