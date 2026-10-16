#!/usr/bin/env bash
# Recursive alias identity must survive union materialization during macro reflection.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/recursive-union-macro.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    printf 'kept_tmp=%s\n' "$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib RecursiveReflectionC
  fun putchar(value : Int32) : Int32
end
class Array(T)
end
class Hash(K, V)
end
module Wire
  alias Field = Nil | Int32 | String | Array(Field) | Hash(String, Field)
end
module Wire
  def self.check
    {% raise "expected five union members" unless Wire::Field.union_types.size == 5 %}
    {% for member in Wire::Field.union_types %}
      {% for arg in member.type_vars %}
        {% if arg.name == "Wire::Field" %}
          {% raise "recursive argument lost alias identity" if arg.union? || arg.class? %}
          RecursiveReflectionC.putchar(65)
        {% end %}
      {% end %}
    {% end %}
  end
end
Wire.check
RecursiveReflectionC.putchar(10)
CRYSTAL

if ! ADAMAS_LLVM_CACHE=0 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/build.resources.json" \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" \
  --no-prelude --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/probe" \
  >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/run.resources.json" \
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
actual="$(sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{/^=== STDOUT ===$/d;/^=== STDERR ===$/d;p;}' "$WORK_DIR/run.log")"
if [[ "$actual" != 'AA' ]] || ! grep -Fq '[EXIT: 0]' "$WORK_DIR/run.log"; then
  cat "$WORK_DIR/run.log" >&2
  printf 'unexpected recursive union macro reflection\n' >&2
  exit 1
fi
printf 'PASS: finite recursive aliases in materialized union macro reflection\n'
