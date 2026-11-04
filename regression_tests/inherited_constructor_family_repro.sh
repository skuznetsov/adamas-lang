#!/usr/bin/env bash
# A source initializer owns new lookup even when an ancestor factory matches.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
adamas="${COMPILER:-${1:-$root/bin/adamas}}"
crystal="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
export ADAMAS_LLVM_CACHE="${ADAMAS_LLVM_CACHE:-0}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/inherited-constructor-family.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/allocate.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class FactoryRoot
  def self.new(value : Int32) : self
    FactoryChild.new(value)
  end

  def initialize
  end

  abstract def read : Int32
end

class FactoryChild < FactoryRoot
  @value : Int32

  def initialize(value)
    super()
    @value = value
  end

  def read : Int32
    @value
  end
end

class FactoryGrandchild < FactoryChild
end

LibC.exit(
  FactoryRoot.new(37).read == 37 &&
  ::FactoryChild.new(23).read == 23 &&
  FactoryGrandchild.new(41).read == 41 ? 0 : 1
)
CRYSTAL

cat >"$tmp/inherit.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Factory
  def self.new(flag : Bool) : Int32
    flag ? 7 : 8
  end
end

class InheritsFactory < Factory
end

class OwnsFactory < Factory
  def initialize(value : Int32)
  end

  def self.new(flag : Bool) : Int32
    flag ? 11 : 12
  end
end

LibC.exit(InheritsFactory.new(true) == 7 && OwnsFactory.new(false) == 12 ? 0 : 1)
CRYSTAL

cat >"$tmp/family.cr" <<'CRYSTAL'
class Factory
  def self.new(value : Bool) : Int32
    99
  end
end

class LocalInitializer < Factory
  def initialize(value : Int32)
  end
end

class InheritsInitializer < LocalInitializer
end
CRYSTAL

cp "$tmp/family.cr" "$tmp/hidden.cr"
printf '\nLocalInitializer.new(true)\n' >>"$tmp/hidden.cr"
cp "$tmp/family.cr" "$tmp/hidden-through-parent.cr"
printf '\nInheritsInitializer.new(true)\n' >>"$tmp/hidden-through-parent.cr"

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
  if "$safe" "$@" >"$log" 2>&1 || ! grep -Eq 'no overload matches|expected argument' "$log"; then
    cat "$log" >&2
    return 1
  fi
  grep -q '\[EXIT: 1\]' "$log"
}

for fixture in allocate inherit; do
  run "$fixture.stock.compile.log" "$crystal" 60 4096 build --prelude=empty "$fixture.cr" -o "$fixture.stock"
  run "$fixture.stock.run.log" "$tmp/$fixture.stock" 5 512
  for mode in lazy eager; do
    ADAMAS_EAGER_HIR=0
    [[ "$mode" != eager ]] || ADAMAS_EAGER_HIR=1
    export ADAMAS_EAGER_HIR
    run "$fixture.$mode.compile.log" "$adamas" 60 4096 --prelude=empty "$fixture.cr" -o "$fixture.$mode"
    run "$fixture.$mode.run.log" "$tmp/$fixture.$mode" 5 512
  done
done

for fixture in hidden hidden-through-parent; do
  reject "$fixture.stock.log" "$crystal" 60 4096 build --prelude=empty "$fixture.cr" -o "$fixture.stock"
  for mode in lazy eager; do
    ADAMAS_EAGER_HIR=0
    [[ "$mode" != eager ]] || ADAMAS_EAGER_HIR=1
    export ADAMAS_EAGER_HIR
    reject "$fixture.$mode.log" "$adamas" 60 4096 --prelude=empty "$fixture.cr" -o "$fixture.$mode"
  done
done

echo 'PASS inherited constructor family (12 stock, lazy, and eager checks)'
