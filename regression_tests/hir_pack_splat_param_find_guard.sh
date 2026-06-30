#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if awk '
  /private def pack_splat_args_for_call/ { in_func = 1 }
  in_func && /splat_param = params\.find/ { bad = 1 }
  in_func && /^    private def / && !/pack_splat_args_for_call/ { exit bad ? 1 : 0 }
  END { if (!in_func) exit 1 }
' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  :
else
  echo "pack_splat_args_for_call must not use Array#find for splat param lookup" >&2
  exit 1
fi

if ! awk '
  /private def pack_splat_args_for_call/ { in_func = 1 }
  in_func && /splat_param : DefParamInfo\? = nil/ { saw_decl = 1 }
  in_func && /params\.each do \|param\|/ && saw_decl { saw_loop = 1 }
  in_func && /splat_param = param/ && saw_loop { saw_assign = 1 }
  in_func && /^    private def / && !/pack_splat_args_for_call/ {
    exit (saw_decl && saw_loop && saw_assign) ? 0 : 1
  }
  END { if (!in_func) exit 1 }
' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  echo "pack_splat_args_for_call must use an explicit splat-param scan" >&2
  exit 1
fi

echo "hir_pack_splat_param_find_guard_ok"
