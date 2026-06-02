#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <debug|release> [output_bin] [extra crystal args...]" >&2
  exit 2
fi

MODE="$1"
shift

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/src/adamas.cr"

case "$MODE" in
  debug)
    CACHE_DIR="${CRYSTAL_CACHE_DIR_DEBUG:-$ROOT_DIR/.cache/original-crystal-debug}"
    RELEASE_FLAG=()
    DEFAULT_OUT="/tmp/stage1_original_debug_cached"
    ;;
  release)
    CACHE_DIR="${CRYSTAL_CACHE_DIR_RELEASE:-$ROOT_DIR/.cache/original-crystal-release}"
    RELEASE_FLAG=(--release)
    DEFAULT_OUT="/tmp/stage1_original_release_cached"
    ;;
  *)
    echo "Unknown mode: $MODE (expected debug or release)" >&2
    exit 2
    ;;
esac

OUT_BIN="$DEFAULT_OUT"
if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
  OUT_BIN="$1"
  shift
fi

mkdir -p "$CACHE_DIR"

echo "[stage1-original] mode=$MODE"
echo "[stage1-original] cache=$CACHE_DIR"
echo "[stage1-original] out=$OUT_BIN"

# M4i0 bootstrap-build contract (Darwin): `crystal build` links with the bundled
# ld64.lld, which IGNORES `-Wl,-stack_size` ("not yet implemented"). A fresh release
# stage1 then gets the default 8MB main-thread stack and the recursive-descent parser
# overflows it on the large self-hosted source (parse_block_body_with_optional_rescue),
# SIGSEGV'ing while building stage2. Force the system linker (/usr/bin/ld), which honors
# `-stack_size`, to give a 64MB stack. Binaries this compiler later produces already link
# via cli.cr's clang -> system ld (s2b/s3b inherit the 64MB stack), so only this
# `crystal build` step needs the override. Verify with `otool -l <bin> | grep -A3 LC_MAIN`.
LINK_FLAGS=()
if [[ "$(uname)" == "Darwin" ]]; then
  LINK_FLAGS+=(--link-flags="-fuse-ld=/usr/bin/ld -Wl,-stack_size,0x4000000")
fi

CRYSTAL_CACHE_DIR="$CACHE_DIR" crystal build "$SRC" "${RELEASE_FLAG[@]}" ${LINK_FLAGS[@]+"${LINK_FLAGS[@]}"} -o "$OUT_BIN" "$@"
