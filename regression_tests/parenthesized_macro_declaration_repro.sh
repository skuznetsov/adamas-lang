#!/usr/bin/env bash
# Spaced declaration arguments must survive arbitrary parenthesized macro calls.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/parenthesized-macro-decl.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat > "$WORK_DIR/macros.cr" <<'CR'
macro declare(decl)
  def self.{{decl.var.id}} : {{decl.type}}
    73
  end
end
macro construct(decl, &constructor)
  {% name = decl.var.id %}
  def self.{{name}} : {{decl.type}}
    {{yield}}
  end
end
CR
cat > "$WORK_DIR/probe.cr" <<'CR'
require "./macros"
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Owner
  declare(value : ::Int32)
  declare bare : ::Int32
  construct(other : ::Int32) do
    41
  end
end
LibC.exit(11) unless Owner.value == 73
LibC.exit(12) unless Owner.bare == 73
LibC.exit(13) unless Owner.other == 41
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
echo "PASS: arbitrary macro declaration arguments, bare control and yielded constructor (--no-prelude)"
