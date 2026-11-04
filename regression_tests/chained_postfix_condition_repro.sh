#!/usr/bin/env bash
# Postfix conditions wrap the preceding expression in source order.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
adamas="${COMPILER:-${1:-$root/bin/adamas}}"
crystal="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld -L/opt/homebrew/lib -lgc}"
export ADAMAS_LLVM_CACHE=0
tmp="$(mktemp -d "${TMPDIR:-/tmp}/chained-postfix-condition.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

cat >scope.cr <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class Base
end

abstract class Controller
  private def page
    items = collect do |item|
      next unless accepts?(item) if enabled?
      item
    rescue ex
      next
    end
    items
  end

  class Nested < Base; end
end

def check(value : Base)
  LibC.exit(0)
end

check(Controller::Nested.new)
CRYSTAL

cat >order.cr <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Conditions
  @visited : Int32 = 0

  def first
    @visited = @visited &* 10 &+ 1
    false
  end

  def second(enabled : Bool)
    @visited = @visited &* 10 &+ 2
    enabled
  end

  def third
    @visited = @visited &* 10 &+ 3
    false
  end

  def run(enabled : Bool)
    value = 5
    value = 7 unless first if second(enabled) unless third
    @visited &* 10 &+ value
  end

  def grouped
    value = 5
    value = 7 unless (first if second(false)) unless third
    @visited &* 10 &+ value
  end
end

LibC.exit(11) unless Conditions.new.run(false) == 325
LibC.exit(12) unless Conditions.new.run(true) == 3217
LibC.exit(13) unless Conditions.new.grouped == 327
LibC.exit(0)
CRYSTAL

cat >rhs_return.cr <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class ReturnModifierCheck
  @visited : Int32 = 0

  def check
    @visited = 1
    false
  end

  def execute(enabled : Bool)
    check || return 1 if enabled
    2
  end

  def grouped(enabled : Bool)
    check || (return 1 if enabled)
    2
  end

  def visited
    @visited
  end
end

probe = ReturnModifierCheck.new
LibC.exit(11) unless probe.execute(false) == 2
LibC.exit(12) unless probe.visited == 0
LibC.exit(13) unless probe.execute(true) == 1
LibC.exit(14) unless probe.visited == 1
probe = ReturnModifierCheck.new
LibC.exit(15) unless probe.grouped(false) == 2
LibC.exit(16) unless probe.visited == 1
LibC.exit(0)
CRYSTAL

check() {
  local mode="$1" fixture output
  shift
  for fixture in scope order rhs_return; do
    output="$fixture.$mode"
    if ! "$safe" "$@" --prelude=empty "$fixture.cr" -o "$output" >"$output.compile.log" 2>&1; then
      cat "$output.compile.log" >&2
      return 1
    fi
    if ! "$safe" "$tmp/$output" 5 512 >"$output.run.log" 2>&1; then
      cat "$output.run.log" >&2
      return 1
    fi
  done
}

check stock "$crystal" 60 4096 build
ADAMAS_EAGER_HIR=0 check lazy "$adamas" 60 4096
ADAMAS_EAGER_HIR=1 check eager "$adamas" 60 4096

echo 'PASS postfix conditions (nine stock, lazy, and eager checks)'
