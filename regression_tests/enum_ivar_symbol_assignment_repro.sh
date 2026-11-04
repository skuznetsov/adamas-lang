#!/usr/bin/env bash
# A symbol literal assigned to an enum field uses the field's nominal type.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
adamas="${COMPILER:-${1:-$root/bin/adamas}}"
crystal="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld -L/opt/homebrew/lib -lgc}"
export ADAMAS_LLVM_CACHE="${ADAMAS_LLVM_CACHE:-0}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/enum-ivar-symbol-assignment.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/valid.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum LexerKind
  Start
  Stop
  Done
end

enum ParserKind
  Done
  Start
  Stop
end

alias State = ParserKind

class Parser
  @kind : State

  def initialize
    @kind = :stop
  end

  def reset : ParserKind
    @kind = :done
  end

  def kind : ParserKind
    @kind
  end
end

class Lexer
  @kind : LexerKind

  def initialize
    @kind = :done
  end

  def kind : LexerKind
    @kind
  end
end

class RawSymbol
  @kind : Symbol

  def initialize
    @kind = :done
  end

  def kind : Symbol
    @kind
  end
end

def recognize(value : Symbol) : Int32
  17
end

parser = Parser.new
LibC.exit(11) unless parser.kind.value == 2
LibC.exit(12) unless Lexer.new.kind.value == 2
LibC.exit(13) unless parser.reset.value == 0 && parser.kind.value == 0
LibC.exit(recognize(RawSymbol.new.kind) == 17 ? 0 : 14)
CRYSTAL

write_invalid() {
  local path="$1" assignment="$2"
  cat >"$path" <<CRYSTAL
enum Kind
  Start
end

class Holder
  @kind : Kind

  def initialize
    $assignment
  end
end

Holder.new
CRYSTAL
}

write_invalid "$tmp/missing.cr" '@kind = :missing'
write_invalid "$tmp/nonliteral.cr" $'value = :start\n    @kind = value'

cd "$tmp"
run() {
  local log="$1"
  shift
  if ! "$safe" "$@" >"$log" 2>&1; then
    cat "$log" >&2
    return 1
  fi
}
reject() {
  local log="$1"
  shift
  if "$safe" "$@" >"$log" 2>&1 ||
     ! rg -q 'must be Kind, not Symbol|no matching enum member' "$log" ||
     ! rg -q '\[EXIT: 1\]' "$log"; then
    cat "$log" >&2
    return 1
  fi
}

run valid.stock.compile.log "$crystal" 60 4096 build --prelude=empty valid.cr -o valid.stock
run valid.stock.run.log "$tmp/valid.stock" 5 512
for fixture in missing nonliteral; do
  reject "$fixture.stock.log" "$crystal" 60 4096 build --prelude=empty "$fixture.cr" -o "$fixture.stock"
done

for mode in lazy eager; do
  ADAMAS_EAGER_HIR=0
  [[ "$mode" != eager ]] || ADAMAS_EAGER_HIR=1
  export ADAMAS_EAGER_HIR
  run "valid.$mode.compile.log" "$adamas" 60 4096 --prelude=empty valid.cr -o "valid.$mode"
  run "valid.$mode.run.log" "$tmp/valid.$mode" 5 512
  for fixture in missing nonliteral; do
    reject "$fixture.$mode.log" "$adamas" 60 4096 --prelude=empty "$fixture.cr" -o "$fixture.$mode"
  done
done

echo 'PASS enum ivar symbol assignment (9 stock, lazy, and eager checks)'
