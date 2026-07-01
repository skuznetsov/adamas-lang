#!/usr/bin/env bash
# H5 contract guard: HIR function registration is not body presence, and
# downstream HIR->MIR lowering must keep a bodyless registered function as an
# unreachable stub instead of treating the initial placeholder terminator as a
# real emitted body.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

crystal spec --no-color spec/hir/function_body_presence_contract_spec.cr

echo "PASS: HIR function body presence contract"
