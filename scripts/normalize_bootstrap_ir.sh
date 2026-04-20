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

perl -pe '
  s{\Q/Users/sergey/Projects/Crystal/crystal_v2_repo\E}{<repo>}g;
  s{/private/var/folders/[^[:space:]\"]+}{<tmp>}g;
  s{/tmp/[^[:space:]\"]+}{<tmp>}g;
  s{crystal_v2_bootstrap[^[:space:]\"]*}{crystal_v2_bootstrap<N>}g;
  s{__crystal_block_proc_[0-9]+}{__crystal_block_proc_<N>}g;
  s{__closure_cell_[0-9]+}{__closure_cell_<N>}g;
  s{__crystal_v2_[A-Za-z0-9_.$-]*[0-9]+}{__crystal_v2_<N>}g;
  s{@\.stub_name_[0-9]+}{@.stub_name_<N>}g;
  s{%[0-9]+}{%<id>}g;
  s{\b(FunctionId|BlockId|ValueId|TypeId)\([0-9]+\)}{$1(<id>)}g;
  s{\b(function|block|value|type)_id=[0-9]+}{$1_id=<id>}g;
  s{\bid=[0-9]+}{id=<id>}g;
  s{\b0x[0-9a-fA-F]+\b}{0x<addr>}g;
  s{line [0-9]+, column [0-9]+}{line <line>, column <col>}g;
  s{:[0-9]+:[0-9]+}{:<line>:<col>}g;
' "$INPUT"
