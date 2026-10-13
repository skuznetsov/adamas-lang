#!/bin/bash
set -euo pipefail

link_args=()
if [[ "$(uname -s)" == "Darwin" ]]; then
  link_args=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

CRYSTAL_CACHE_DIR="$PWD/.cache/debug/" crystal build -s -p -d src/adamas.cr \
  ${link_args[@]+"${link_args[@]}"} -o bin/adamas_deb
