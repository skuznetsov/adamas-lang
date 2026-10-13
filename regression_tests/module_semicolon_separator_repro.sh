#!/usr/bin/env bash
# `module Mo; end` on one line: parse_module skipped only newlines after the
# header and between body statements (parse_class also skips `;`), so the
# `;` derailed the module body and swallowed the rest of the file.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module_semicolon.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_module_semi.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Mo; end
module Mg(T); end
module Mb; def self.x; 1; end; end
# A swallowed tail falls off main with status 0, so success is status 3.
LibC.exit(Mb.x == 1 ? 3 : 1)
CR
for name in np_module_semi; do
  flags=()
  [[ "$name" == np_* ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT 3):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo module_semicolon_separator_repro_ok
