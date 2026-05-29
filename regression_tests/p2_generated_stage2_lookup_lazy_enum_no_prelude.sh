#!/usr/bin/env bash
# Generated-stage2 guard for two adjacent self-host frontiers:
# 1. lookup_function_def_for_call must not confuse function_def_overloads(...)
#    with the @function_def_overloads ivar getter and then treat overload keys
#    as a Hash.
# 2. no-prelude private-class lowering must not enter lazy enum filesystem
#    discovery for ordinary class types.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "p2_generated_stage2_lookup_lazy_enum_failed: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_generated_stage2_lookup_lazy_enum_XXXXXX)"
GENERATED_S2="$TMP_DIR/generated_s2"
BUILD_LOG="$TMP_DIR/stage2_build.log"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_generated_stage2_lookup_lazy_enum] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
  "$ROOT_DIR/src/adamas.cr" -o "$GENERATED_S2" >"$BUILD_LOG" 2>&1

if [[ ! -x "$GENERATED_S2" ]]; then
  echo "p2_generated_stage2_lookup_lazy_enum_failed: missing generated stage2 compiler" >&2
  tail -100 "$BUILD_LOG" >&2 || true
  exit 1
fi

STRING_SRC="$TMP_DIR/string_includes.cr"
STRING_LOG="$TMP_DIR/string_includes.log"
PRIVATE_SRC="$TMP_DIR/private_class.cr"
PRIVATE_LOG="$TMP_DIR/private_class.log"

cat >"$STRING_SRC" <<'CR'
class Object
end

"Hidden.new".includes?("$$block")
CR

cat >"$PRIVATE_SRC" <<'CR'
class Object
end

private class Hidden
  def value : Int32
    1
  end
end

Hidden.new.value
CR

"$ROOT_DIR/scripts/run_safe.sh" "$GENERATED_S2" 10 1024 \
  "$STRING_SRC" --no-prelude --emit hir --no-link -o "$TMP_DIR/string_includes" \
  >"$STRING_LOG" 2>&1

if grep -Eq 'STUB CALLED: Hash|Hash\$Heach|Hash\$LString\$C\$_Array' "$STRING_LOG"; then
  echo "p2_generated_stage2_lookup_lazy_enum_failed: overload-key lookup regressed to Hash stubs" >&2
  tail -120 "$STRING_LOG" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$GENERATED_S2" 10 1024 \
  "$PRIVATE_SRC" --no-prelude --emit hir --no-link -o "$TMP_DIR/private_class" \
  >"$PRIVATE_LOG" 2>&1

if grep -Eq 'Segmentation fault|Index out of bounds|lazy_discover_enum_from_source|Dir\$Dglob|Set\(String\)#includes' "$PRIVATE_LOG"; then
  echo "p2_generated_stage2_lookup_lazy_enum_failed: private class regressed into lazy enum discovery" >&2
  tail -140 "$PRIVATE_LOG" >&2 || true
  exit 1
fi

echo "p2_generated_stage2_lookup_lazy_enum_no_prelude_ok"
