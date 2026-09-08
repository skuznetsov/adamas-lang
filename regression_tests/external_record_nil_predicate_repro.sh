#!/usr/bin/env bash
# Modern external record macros must distinguish absent and explicit defaults.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
: "${CRYSTAL_PATH:?Set CRYSTAL_PATH to the external Crystal src directory}"
if [[ ! -f "$CRYSTAL_PATH/macros.cr" ]]; then
  echo "Expected a single external Crystal src directory in CRYSTAL_PATH" >&2
  exit 2
fi
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/external-record-nil.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat > "$WORK_DIR/probe.cr" <<CR
require "$CRYSTAL_PATH/macros"

lib LibC
  fun exit(status : Int32) : NoReturn
end

class Owner
  record Handler, value : Int32
end
record Defaults, value : Int32 = 41, enabled : Bool = false, optional : Int32? = nil

handler = Owner::Handler.new(73)
LibC.exit(11) unless handler.value == 73
defaults = Defaults.new
LibC.exit(12) unless defaults.value == 41
LibC.exit(13) if defaults.enabled
LibC.exit(14) unless defaults.optional.nil?
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 8192 "$WORK_DIR/probe.cr" --no-prelude -o "$WORK_DIR/probe" > "$WORK_DIR/compile.log" 2>&1; then
  cat "$WORK_DIR/compile.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 > "$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/compile.log" "$WORK_DIR/run.log" >&2
  exit 1
fi
echo "PASS: external record absent, numeric, false and explicit nil defaults (--no-prelude)"
