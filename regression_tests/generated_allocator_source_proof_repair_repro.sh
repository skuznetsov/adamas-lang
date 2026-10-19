#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CRYSTAL_HINT="$(printenv CRYSTAL_BIN || true)"
if [[ -z "$CRYSTAL_HINT" ]]; then
  CRYSTAL_HINT=crystal
fi
if [[ "$CRYSTAL_HINT" == */* ]]; then
  CRYSTAL_BIN_PATH="$(cd "$(dirname "$CRYSTAL_HINT")" && pwd -P)/$(basename "$CRYSTAL_HINT")"
else
  CRYSTAL_BIN_PATH="$(command -v "$CRYSTAL_HINT" || true)"
fi
if [[ -z "$CRYSTAL_BIN_PATH" || ! -x "$CRYSTAL_BIN_PATH" ]]; then
  printf 'missing Crystal executable: %s\n' "$CRYSTAL_HINT" >&2
  exit 2
fi

SPEC_ARGS=(spec --no-color "$ROOT_DIR/spec/hir/generated_allocator_source_proof_repair_spec.cr")
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then
  SPEC_ARGS+=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS")
fi
"$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL_BIN_PATH" 300 8192 "${SPEC_ARGS[@]}"

printf 'PASS: generated allocator source proof survives a qualified result-type repair\n'
