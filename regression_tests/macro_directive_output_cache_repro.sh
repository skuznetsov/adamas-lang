#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOST_COMPILER="${1:-crystal}"
if [[ $# -gt 0 ]]; then shift; fi

# The host compiles the compiler's parser/cache regression; run_safe also bounds
# the generated spec process and removes it if the test exceeds its limits.
"$ROOT/scripts/run_safe.sh" "$HOST_COMPILER" 120 8192 spec \
  "$ROOT/spec/parser/macro_directive_output_cache_spec.cr" \
  "$ROOT/spec/semantic/macro_directive_output_consumer_spec.cr" "$@"
