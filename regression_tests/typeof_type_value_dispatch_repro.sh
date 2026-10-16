#!/usr/bin/env bash
# A typeof expression is a type value for member dispatch, without evaluation.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typeof-type-value-dispatch.XXXXXX")"
cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT
if [[ ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL" ]]; then
  echo "ERROR: candidate and original compilers must be executable" >&2
  exit 2
fi
cat >"$WORK_DIR/main.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end
class TypeofValueProbe
end
class NamedTypeofValueProbe
  def self.name : String
    "custom-type-name"
  end
end
def type_only_side_effect : Int32
  LibC.putchar(88)
  65
end
puts typeof(1).name
puts typeof("x").name()
puts typeof(TypeofValueProbe.new).name
puts typeof(1, 2_i64).name
puts typeof(type_only_side_effect).name
puts typeof(NamedTypeofValueProbe.new).name
puts typeof(1, 2_i64).to_s
puts typeof(1, 2_i64).inspect
puts typeof(1, 2_i64).name()
puts typeof(type_only_side_effect).name()
puts typeof(NamedTypeofValueProbe.new).name()
CRYSTAL
cat >"$WORK_DIR/expected" <<'EXPECTED'
Int32
String
TypeofValueProbe
(Int32 | Int64)
Int32
custom-type-name
(Int32 | Int64)
(Int32 | Int64)
(Int32 | Int64)
Int32
custom-type-name
EXPECTED
for stage in original candidate; do
  compiler="$COMPILER"
  args=("$WORK_DIR/main.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/$stage")
  if [[ "$stage" == "original" ]]; then
    compiler="$ORIGINAL_CRYSTAL"
    args=(build "$WORK_DIR/main.cr" -o "$WORK_DIR/$stage" --no-debug --error-trace --link-flags=-fuse-ld=/usr/bin/ld)
  fi
  if ! CRYSTAL_CACHE_DIR="$WORK_DIR/$stage.cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.build.resources" \
      "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 180 8192 "${args[@]}" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
    echo "FAIL[$stage]: compilation failed" >&2
    tail -20 "$WORK_DIR/$stage.build.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.run.resources" \
      "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$stage" 10 512 \
      >"$WORK_DIR/$stage.actual" 2>"$WORK_DIR/$stage.run.log"; then
    echo "FAIL[$stage]: runtime failed" >&2
    tail -20 "$WORK_DIR/$stage.run.log" >&2
    exit 1
  fi
  if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/$stage.actual" >&2; then
    echo "FAIL[$stage]: type-value output differs or typeof evaluated its argument" >&2
    exit 1
  fi
  echo "PASS[$stage]: typeof member dispatch, union display, override and non-evaluation agree"
done
