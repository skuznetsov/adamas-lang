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

chain_manifest="$OUT_DIR/bootstrap_chain.manifest"
if [[ ! -s "$chain_manifest" ]]; then
  echo "error: bootstrap chain did not produce a provenance manifest: $chain_manifest" >&2
  exit 1
fi

names=(s1_bootstrap s2b s3b s4b s5b)
for ((i = 1; i <= STAGES && i <= ${#names[@]}; i++)); do
  src="cv2_s${i}"
  dst="${names[$((i - 1))]}"
  if [[ ! -f "$OUT_DIR/$src" || -L "$OUT_DIR/$src" || ! -x "$OUT_DIR/$src" || ! -s "$OUT_DIR/$src" ]]; then
    echo "error: expected fresh stage artifact missing, empty, or not executable: $OUT_DIR/$src" >&2
    exit 1
  fi
  ln -sf "$src" "$OUT_DIR/$dst"
done

manifest="$OUT_DIR/bootstrap_stages.manifest"
safe_manifest_value() {
  printf '%s' "$1" | LC_ALL=C tr -c '[:print:]' '_'
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$path" | awk '{print $1}'
  else
    printf 'unavailable'
  fi
}

manifest_tmp="$manifest.tmp.$$"
{
  cat "$chain_manifest"
  echo "stable_manifest_format_version=2"
  echo "stable_manifest_run_id=$(awk -F= '$1 == "run_id" { print substr($0, index($0, "=") + 1); exit }' "$chain_manifest")"
  echo "stable_repo=$(safe_manifest_value "$ROOT_DIR")"
  echo "stable_wrapper_sha256=$(sha256_file "$ROOT_DIR/scripts/build_bootstrap_stages.sh")"
  echo "stable_stages=$(safe_manifest_value "$STAGES")"
  echo "stable_out=$(safe_manifest_value "$OUT_DIR")"
  for ((i = 1; i <= STAGES && i <= ${#names[@]}; i++)); do
    alias="${names[$((i - 1))]}"
    target="cv2_s${i}"
    echo "${alias}=${target}"
    echo "${alias}_sha256=$(sha256_file "$OUT_DIR/$target")"
  done
} >"$manifest_tmp" || {
  echo "error: unable to write stable bootstrap manifest: $manifest" >&2
  exit 1
}
mv -f "$manifest_tmp" "$manifest" || {
  echo "error: unable to install stable bootstrap manifest: $manifest" >&2
  exit 1
}

run_id="$(awk -F= '$1 == "run_id" { print substr($0, index($0, "=") + 1); exit }' "$manifest")"
manifest_sha256="$(sha256_file "$manifest")"
echo "bootstrap_stage_artifacts_ok run_id=$(safe_manifest_value "$run_id") manifest_sha256=$manifest_sha256 out=$(safe_manifest_value "$OUT_DIR") manifest=$(safe_manifest_value "$manifest")"
