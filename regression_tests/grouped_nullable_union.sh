#!/usr/bin/env bash
# Grouping and redundant nilability must not add another runtime union tag.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/grouped_nullable_union.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
failures=0

run_case() {
  local name="$1" annotation="$2" literal="$3" alias_decl="${4:-}"
  cat > "$TMP_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end
$alias_decl
def resolve(flag : Bool) : $annotation
  flag ? $literal : nil
end
value = resolve(true)
if value
  LibC.exit(71) unless value == $literal
else
  LibC.exit(72)
end
LibC.exit(73) unless resolve(false).nil?
LibC.exit(0)
CR
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 45 4096 \
      "$TMP_DIR/$name.cr" --no-prelude -o "$TMP_DIR/$name" > "$TMP_DIR/$name.compile.log" 2>&1; then
    echo "FAIL[$name]: compilation"
    cat "$TMP_DIR/$name.compile.log"
    failures=$((failures + 1))
  elif ! "$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/$name" 5 512 > "$TMP_DIR/$name.run.log" 2>&1; then
    echo "FAIL[$name]: runtime"
    cat "$TMP_DIR/$name.run.log"
    failures=$((failures + 1))
  else
    echo "PASS[$name]"
  fi
}

run_case flat_control 'Int64?' '42_i64'
run_case grouped_nullable '(Int64 | Nil)?' '42_i64'
run_case nested_groups '((Int64 | Nil))?' '-17_i64'
run_case grouped_multiarm '(Int32 | Int64)?' '42_i64'
run_case grouped_unsigned '(UInt64 | Nil)?' '4294967297_u64'
run_case grouped_alias 'MaybeCount?' '42_i64' 'alias MaybeCount = (Int64 | Nil)'

if [[ "$failures" -ne 0 ]]; then
  echo "$failures grouped nullable union regression(s) failed"
  exit 1
fi
