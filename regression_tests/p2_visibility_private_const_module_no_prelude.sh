#!/usr/bin/env bash
# No-prelude guard for the stage2 visibility/constant frontier that is already
# expected to be green: private uppercase constants must remain constants, and
# private module wrappers must not require an abort-stubbed arena helper path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_visibility_private_const_module_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

compile_ok() {
  local name="$1"
  local src="$TMP_DIR/$name.cr"
  local out="$TMP_DIR/$name"
  local log="$TMP_DIR/$name.log"
  cat >"$src"
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 10 1024 \
    "$src" --no-prelude --emit hir --no-link -o "$out" >"$log" 2>&1
}

compile_ok private_constant <<'CR'
class Object
end

private VALUE = 1
VALUE
CR

compile_ok private_module <<'CR'
class Object
end

private module M
end
CR

echo "p2_visibility_private_const_module_no_prelude_ok"
