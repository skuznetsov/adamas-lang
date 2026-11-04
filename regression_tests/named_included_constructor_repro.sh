#!/usr/bin/env bash
# Named new can select the nearest included initializer family after a local miss.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
adamas="${COMPILER:-${1:-$root/bin/adamas}}"
crystal="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld -L/opt/homebrew/lib -lgc}"
export ADAMAS_LLVM_CACHE="${ADAMAS_LLVM_CACHE:-0}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/named-included-constructor.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

write_fixture() {
  local fixture="$1" second_label="$2" direct_label="$3" direct_position="$4" call="$5" expected="$6"
  {
    cat <<CRYSTAL
lib LibC
  fun exit(status : Int32) : NoReturn
end

module First
  def initialize(*, _value @value : Int32)
    @result = 21
  end
end

module Second
  def initialize(*, $second_label @value : Int32)
    @result = 22
  end
end

alias Engine = Second

class Factory
  @value : Int32
  @result : Int32

  def self.new(source : Int32) : self
    new(_value: source)
  end
CRYSTAL
    if [[ "$direct_position" == before ]]; then
      printf '  def initialize(*, %s @value : Int32)\n    @result = 23\n  end\n' "$direct_label"
    fi
    printf '  include First\n  include Engine\n'
    if [[ "$direct_position" == after ]]; then
      printf '  def initialize(*, %s @value : Int32)\n    @result = 23\n  end\n' "$direct_label"
    fi
    cat <<CRYSTAL
  def result : Int32
    @result
  end
end

LibC.exit(Factory.new($call).result == $expected ? 0 : 11)
CRYSTAL
  } >"$fixture.cr"
}

write_fixture included _value _value absent 7 22
write_fixture named _value _value absent '_value: 7' 22
write_fixture direct_before _value _value before 7 23
write_fixture direct_after _value _value after 7 23
write_fixture class_boundary _value _other before 7 22
write_fixture module_boundary _other _value absent 7 21
write_fixture wrong_type _value _value absent '_value: true' 22

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
     ! rg -q 'no overload matches|missing argument' "$log" ||
     ! rg -q '\[EXIT: 1\]' "$log"; then
    cat "$log" >&2
    return 1
  fi
}

for mode in stock lazy eager; do
  compiler="$adamas"
  if [[ "$mode" == stock ]]; then
    compiler="$crystal"
  fi
  ADAMAS_EAGER_HIR=0
  [[ "$mode" != eager ]] || ADAMAS_EAGER_HIR=1
  export ADAMAS_EAGER_HIR
  for fixture in included named direct_before direct_after; do
    run "$fixture.$mode.compile.log" "$compiler" 60 4096 build --prelude=empty "$fixture.cr" -o "$fixture.$mode"
    run "$fixture.$mode.run.log" "$tmp/$fixture.$mode" 5 512
  done
  for fixture in class_boundary module_boundary wrong_type; do
    reject "$fixture.$mode.log" "$compiler" 60 4096 build --prelude=empty "$fixture.cr" -o "$fixture.$mode"
  done
done

echo 'PASS named included constructor (21 stock, lazy, and eager checks)'
