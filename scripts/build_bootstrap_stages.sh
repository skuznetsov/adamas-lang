#!/usr/bin/env bash
# Build the canonical bootstrap ladder and expose stable artifact names.
#
# This is a thin wrapper over bootstrap_chain.sh. It does not change build
# semantics; it only gives the original -> s1 -> s2b -> ... chain predictable
# names for follow-up IR emission/comparison scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${BOOTSTRAP_STAGE_OUT:-/tmp/adamas_bootstrap_stages}"
STAGES="${BOOTSTRAP_CHAIN_STAGES:-5}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build_bootstrap_stages.sh [--out DIR] [--stages N] [bootstrap_chain args...]

Default:
  --out /tmp/adamas_bootstrap_stages --stages 5

Stable names created inside DIR:
  s1_bootstrap -> cv2_s1
  s2b          -> cv2_s2
  s3b          -> cv2_s3
  s4b          -> cv2_s4
  s5b          -> cv2_s5
USAGE
}

CHAIN_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    --stages)
      STAGES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      CHAIN_ARGS+=("$1")
      shift
      ;;
  esac
done

mkdir -p "$OUT_DIR"

if [[ ${#CHAIN_ARGS[@]} -gt 0 ]]; then
  "$ROOT_DIR/scripts/bootstrap_chain.sh" --out "$OUT_DIR" --stages "$STAGES" "${CHAIN_ARGS[@]}"
else
  "$ROOT_DIR/scripts/bootstrap_chain.sh" --out "$OUT_DIR" --stages "$STAGES"
fi

names=(s1_bootstrap s2b s3b s4b s5b)
for ((i = 1; i <= STAGES && i <= ${#names[@]}; i++)); do
  src="cv2_s${i}"
  dst="${names[$((i - 1))]}"
  if [[ ! -x "$OUT_DIR/$src" ]]; then
    echo "error: expected stage artifact missing or not executable: $OUT_DIR/$src" >&2
    exit 1
  fi
  ln -sf "$src" "$OUT_DIR/$dst"
done

manifest="$OUT_DIR/bootstrap_stages.manifest"
{
  echo "repo=$ROOT_DIR"
  echo "stages=$STAGES"
  echo "out=$OUT_DIR"
  for ((i = 1; i <= STAGES && i <= ${#names[@]}; i++)); do
    echo "${names[$((i - 1))]}=$OUT_DIR/${names[$((i - 1))]}"
  done
} >"$manifest"

echo "bootstrap_stage_artifacts_ok out=$OUT_DIR manifest=$manifest"
