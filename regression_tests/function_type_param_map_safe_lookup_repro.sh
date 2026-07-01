#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:-bin/adamas}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_CR="${TMPDIR:-/tmp}/adamas_function_type_param_map_safe_lookup_repro.cr"
TMP_BIN="${TMPDIR:-/tmp}/adamas_function_type_param_map_safe_lookup_repro"
TMP_LOG="${TMPDIR:-/tmp}/adamas_function_type_param_map_safe_lookup_repro.log"

if rg -q '@function_type_param_maps\.dig\?' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  echo "FAIL: @function_type_param_maps must not use nested Hash#dig? in self-hosted metadata lookups" >&2
  exit 1
fi

cat > "$TMP_CR" <<'CR'
maps = Hash(String, Hash(String, String)).new
maps["f"] = {"__block_return__" => "String"}

if maps.has_key?("f")
  inner = maps["f"]
  if inner.has_key?("__block_return__")
    puts inner["__block_return__"]
  end
end
CR

"$COMPILER" "$TMP_CR" -o "$TMP_BIN" >"$TMP_LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$TMP_BIN" 5 512 >"$TMP_LOG.run" 2>&1

if ! grep -q '^String$' "$TMP_LOG.run"; then
  echo "FAIL: safe nested Hash lookup did not return String" >&2
  cat "$TMP_LOG" >&2 || true
  cat "$TMP_LOG.run" >&2 || true
  exit 1
fi

rm -f "$TMP_CR" "$TMP_BIN" "$TMP_LOG" "$TMP_LOG.run" "$TMP_BIN.ll" "$TMP_BIN.dwarf"
echo "PASS function_type_param_map_safe_lookup"
