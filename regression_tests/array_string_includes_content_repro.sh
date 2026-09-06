#!/usr/bin/env bash
# Array(String)#includes? must compare contents even for distinct allocations.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array-string-includes.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == 1 ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def build(prefix : String) : String
  prefix + "(String, Nil)"
end

names = [build("First"), build("Hash")]
LibC.exit(11) unless names.includes?("First(String, Nil)")
LibC.exit(12) unless names.includes?("Hash(String, Nil)")
LibC.exit(13) if names.includes?("Hash(String, String)")
LibC.exit(14) if names.includes?("Hash")
empty = [] of String
LibC.exit(15) if empty.includes?("Hash(String, Nil)")
numbers = [17, 23]
LibC.exit(16) unless numbers.includes?(23)
LibC.exit(17) if numbers.includes?(19)
LibC.exit(0)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 45 2048 \
    --no-prelude "$WORK_DIR/repro.cr" -o "$WORK_DIR/repro" >"$WORK_DIR/compile.log" 2>&1; then
  tail -30 "$WORK_DIR/compile.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo "PASS: Array(String)#includes? uses content equality and preserves primitive controls"
