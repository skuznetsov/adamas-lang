#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for factory in \
  'def self.with_receiver(' \
  'def self.with_receiver_virtual(' \
  'def self.with_receiver_block(' \
  'def configure_with_receiver(' \
  'def configure_with_receiver_block('
do
  if ! grep -Fq "$factory" "$ROOT_DIR/src/compiler/hir/hir.cr"; then
    echo "missing HIR::Call receiver factory/configurator: $factory" >&2
    exit 1
  fi
done

if ! grep -Fq 'Call.with_receiver(' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr" ||
   ! grep -Fq 'Call.with_receiver_virtual(' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr" ||
   ! grep -Fq 'Call.with_receiver_block(' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  echo "lower_call must construct receiver calls through named HIR::Call factories" >&2
  exit 1
fi

if awk '
  /call = if receiver_id/ { in_receiver = 1 }
  in_receiver && /elsif has_block_call && block_id/ { exit bad ? 1 : 0 }
  in_receiver && /Call\.new\(ctx\.next_id, return_type, recv_id, emit_method_name, args/ { bad = 1 }
  END { if (!in_receiver) exit 1 }
' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  :
else
  echo "lower_call receiver branch must not call overloaded Call.new directly" >&2
  exit 1
fi

echo "hir_call_receiver_factory_guard_ok"
