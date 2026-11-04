#!/usr/bin/env bash
# A generated enum setter uses its destination type to bind a symbol literal.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
adamas="${COMPILER:-${1:-$root/bin/adamas}}"
crystal="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld -L/opt/homebrew/lib -lgc}"
export ADAMAS_LLVM_CACHE=0
tmp="$(mktemp -d "${TMPDIR:-/tmp}/enum-property-symbol-assignment.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# Stock Crystal provides this macro in its prelude. Define its typed form
# locally so the same source also exercises Adamas with an empty prelude.
cat >base.cr <<'CRYSTAL'
macro property(decl)
  @{{decl}}
  def {{decl.var}}
    @{{decl.var}}
  end
  def {{decl.var}}=(@{{decl.var}} : {{decl.type}})
  end
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Kind
  Start
  Done
end

class Holder
  property kind : Kind

  def initialize
    @kind = :start
  end
end
CRYSTAL

cp base.cr valid.cr
cat >>valid.cr <<'CRYSTAL'

class Explicit
  property kind : Kind

  def initialize
    @kind = :start
  end

  def kind=(value : Symbol)
    @kind = :done
  end
end

holder = Holder.new
assigned = holder.kind = :done
LibC.exit(11) unless holder.kind.value == 1
LibC.exit(12) unless assigned.value == 1
explicit = Explicit.new
explicit.kind = :not_a_member
LibC.exit(explicit.kind.value == 1 ? 0 : 13)
CRYSTAL

cp base.cr missing.cr
echo 'Holder.new.kind = :missing' >>missing.cr
cp base.cr nonliteral.cr
printf '%s\n' 'kind = :done' 'Holder.new.kind = kind' >>nonliteral.cr

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
     ! rg -qi "be Kind, not Symbol|no matching enum member|match a member of enum Kind" "$log" ||
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

echo 'PASS enum property symbol assignment (9 stock, lazy, and eager checks)'
