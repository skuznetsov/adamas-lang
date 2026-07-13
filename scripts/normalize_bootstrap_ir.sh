#!/usr/bin/env bash
# Normalize only known non-semantic noise in HIR/MIR/LLVM bootstrap dumps.
#
# This is intentionally conservative. If a structural diff survives this script,
# it should block the bootstrap semantic-equivalence gate until understood.
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [dump-file]" >&2
  exit 2
fi

INPUT="${1:-/dev/stdin}"
if [[ ! -f "$INPUT" && "$INPUT" != "/dev/stdin" ]]; then
  echo "error: input not found: $INPUT" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$REPO_ROOT" perl -pe '
  BEGIN { $repo = quotemeta($ENV{"REPO_ROOT"}); }
  s{$repo}{<repo>}g;
  s{/private/var/folders/[^[:space:]\"]+}{<tmp>}g;
  s{/tmp/[^[:space:]\"]+}{<tmp>}g;
  s{adamas_bootstrap[^[:space:]\"]*}{adamas_bootstrap<N>}g;
' "$INPUT"
