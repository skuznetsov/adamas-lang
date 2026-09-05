#!/usr/bin/env bash
# A concrete union member and a named argument must retain the initializer
# that accepts the supplied arena, including its object identity.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
CASE="${2:-constructor}"
case "$CASE" in
  constructor|--enum-only) ;;
  *) echo "Usage: $0 [compiler] [--enum-only]" >&2; exit 2 ;;
esac
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_constructor_identity.XXXXXX")" || exit 2
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat > "$TMP_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module CtorIdentityProbe
  class Lexer
  end
  class AstArena
    @marker : Int32
    def marker : Int32
      @marker
    end
    def marker=(value : Int32)
      @marker = value
    end
    def initialize(@marker : Int32 = 1)
    end
  end
  class VirtualArena
    def marker : Int32
      2
    end
  end
  class PageArena
    def marker : Int32
      3
    end
  end
  alias ArenaLike = AstArena | VirtualArena | PageArena
  class Parser
    @arena : ArenaLike
    @recovery_mode : Bool
    def initialize(lexer : Lexer, *, @recovery_mode : Bool = false)
      @arena = AstArena.new(99)
    end
    def initialize(lexer : Lexer, @arena : ArenaLike, *, @recovery_mode : Bool = false)
    end
    def marker : Int32
      @arena.marker
    end
    def recovery_mode? : Bool
      @recovery_mode
    end
  end
end
# This also exercises the compiler's real Parser.new with an external arena
# when a produced stage expands the enum macro literal.
enum MacroChoice
  {% if true %}
    Selected = 42
  {% else %}
    Rejected = 99
  {% end %}
end
LibC.exit(10) unless MacroChoice::Selected.value == 42

arena = CtorIdentityProbe::AstArena.new(42)
p = CtorIdentityProbe::Parser.new(CtorIdentityProbe::Lexer.new, arena, recovery_mode: true)
LibC.exit(7) unless p.marker == 42
LibC.exit(8) unless p.recovery_mode?
arena.marker = 43
LibC.exit(p.marker == 43 ? 0 : 9)
CR

# Isolate the real macro parser from unrelated produced-stage call/phi
# lowering failures in the larger identity fixture.
if [[ "$CASE" == "--enum-only" ]]; then
  cat > "$TMP_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum MacroChoice
  {% if true %}
    Selected = 42
  {% else %}
    Rejected = 99
  {% end %}
end
LibC.exit(MacroChoice::Selected.value - 42)
CR
fi

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
  "$TMP_DIR/repro.cr" --no-prelude \
  -o "$TMP_DIR/repro" > "$TMP_DIR/compile.log" 2>&1
compile_rc=$?
if [[ "$compile_rc" -ne 0 ]]; then
  cat "$TMP_DIR/compile.log"
  exit 1
fi
if [[ ! -x "$TMP_DIR/repro" ]]; then
  echo "FAIL: compiler produced no executable"
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/repro" 5 512 > "$TMP_DIR/runtime.log" 2>&1
runtime_rc=$?
if [[ "$runtime_rc" -ne 0 ]]; then
  cat "$TMP_DIR/runtime.log"
  exit 1
fi
if [[ "$CASE" == "--enum-only" ]]; then
  echo "PASS: enum macro roots retain the parser arena"
else
  echo "PASS: union positional initializer retains the supplied arena"
fi
