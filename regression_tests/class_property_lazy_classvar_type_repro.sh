#!/usr/bin/env bash
# Regression: macro-expanded `class_property(x : T) { ... }` must register the
# generated `@@x : T?` class variable type before lowering the generated getter.
# Without that, the getter's classvar read is typed as Void, `.nil?` is folded
# away, and the getter returns null instead of evaluating the lazy fallback.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/class_property_lazy_cvar.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat > "$SRC" <<'CR'
class Foo
  class_property(local : String) { "fallback" }
end

puts Foo.local
CR

"$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1

if grep -Fxq "fallback" "$RUN_LOG"; then
  echo "class_property_lazy_classvar_type_repro_ok"
  exit 0
fi

echo "class_property_lazy_classvar_type_repro_failed" >&2
tail -80 "$COMPILE_LOG" >&2 || true
tail -80 "$RUN_LOG" >&2 || true
exit 1
