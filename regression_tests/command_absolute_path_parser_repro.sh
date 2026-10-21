#!/usr/bin/env bash
# Exercise command-argument and ordinary path ASTs independently of lowering.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
compiler="${CRYSTAL:-crystal}"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas_command_absolute_path.XXXXXX")"
trap 'rm -rf "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"
"$root/scripts/run_safe.sh" "$compiler" 120 4096 build \
  "$root/spec/parser/parser_path_spec.cr" --no-debug --error-trace \
  -o "$work/parser_path_spec" "$@"
"$root/scripts/run_safe.sh" "$work/parser_path_spec" 10 512
