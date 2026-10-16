#!/usr/bin/env bash
# Macro regex replacement must preserve values and receiver AST kinds.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-regex-replacement.XXXXXX")"
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
puts({{ "Outer::Inner".gsub(/:/, "_") }})
puts({{ "Outer::Inner".id.gsub(/:/, "_").stringify }})
puts({{ "V2".gsub(/^v/i, "") }})
puts({{ "v2.8".gsub(/^v(.*)$/, "\\1") }})
puts({{ "ab".gsub(/(?=b)/, "x") }})
puts({{ "A:B".gsub(/:/, "_").class_name }})
puts({{ "A:B".id.gsub(/:/, "_").class_name }})
CRYSTAL
cat >"$WORK_DIR/expected" <<'EXPECTED'
Outer__Inner
Outer__Inner
2
2.8
axb
StringLiteral
MacroId
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
    echo "FAIL[$stage]: macro regex replacement output differs" >&2
    exit 1
  fi
  echo "PASS[$stage]: regex replacement values and node kinds agree"
done
