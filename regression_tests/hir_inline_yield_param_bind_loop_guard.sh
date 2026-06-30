#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if awk '
  /private def inline_yield_function/ { in_func = 1 }
  in_func && /Bind function parameters to call arguments/ { in_bind = 1 }
  in_bind && /each_param_with_index\(params\)/ { bad = 1 }
  in_bind && /while param_idx < params\.size/ { saw_loop = 1 }
  in_bind && /param = params\.unsafe_fetch\(param_idx\)/ { saw_fetch = 1 }
  in_bind && /arg_idx \+= 1/ { saw_arg_step = 1 }
  in_bind && /Lower function body with yield substitution/ {
    exit (!bad && saw_loop && saw_fetch && saw_arg_step) ? 0 : 1
  }
  /^    private def / && in_func && !/inline_yield_function/ { exit 1 }
  END { if (!in_func || !in_bind) exit 1 }
' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  :
else
  echo "inline_yield_function must bind callee params with an explicit loop, not each_param_with_index" >&2
  exit 1
fi

echo "hir_inline_yield_param_bind_loop_guard_ok"
