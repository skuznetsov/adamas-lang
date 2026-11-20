#!/usr/bin/env bash
# Case narrows a live local even when it was assigned from the same-named method.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
adamas="${1:?usage: $0 /path/to/adamas}"
crystal="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-case-local-binding.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

link_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  link_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="-fuse-ld=/usr/bin/ld"
fi

cat > common.cr <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Slice(T)
  def initialize(@value : T)
  end

  def first : T
    @value
  end
end

class Parameter
  def initialize(@value : Slice(UInt8)?)
  end

  def name : Slice(UInt8)?
    @value
  end

  def clear
    @value = nil
  end
end

def exact(value : Slice(UInt8)) : UInt8
  value.first
end

def raise(message) : NoReturn
  LibC.exit(99)
end
CRYSTAL

cat > positive.cr <<'CRYSTAL'
require "./common"

def from_parameter(param : Parameter) : UInt8
  name = param.name
  case name
  when Slice(UInt8)
    exact(name)
  when String
    44_u8
  else
    55_u8
  end
end

class Parameter
  def from_same_named_bare_call : UInt8
    name = name()
    case name
    when Slice(UInt8)
      exact(name)
    else
      55_u8
    end
  end

  def bare_method_stays_callable : Bool
    first = name
    case name
    when Slice(UInt8)
      clear
      !first.nil? && name.nil?
    else
      false
    end
  end
end

some = Parameter.new(Slice(UInt8).new(42_u8))
none = Parameter.new(nil)
LibC.exit(1) unless from_parameter(some) == 42_u8 && from_parameter(none) == 55_u8
LibC.exit(2) unless some.from_same_named_bare_call == 42_u8 && none.from_same_named_bare_call == 55_u8
LibC.exit(3) unless some.bare_method_stays_callable
CRYSTAL

cat > unbound.cr <<'CRYSTAL'
require "./common"

class Parameter
  def visit : UInt8
    case name
    when Slice(UInt8)
      clear
      exact(name)
    else
      55_u8
    end
  end
end

Parameter.new(Slice(UInt8).new(42_u8)).visit
CRYSTAL

cat > reassigned.cr <<'CRYSTAL'
require "./common"

def visit(param : Parameter) : UInt8
  name = param.name
  case name
  when Slice(UInt8)
    name = nil
    exact(name)
  else
    55_u8
  end
end

visit(Parameter.new(Slice(UInt8).new(42_u8)))
CRYSTAL

compile() {
  local mode="$1" source="$2" binary="$3"
  case "$mode" in
    crystal) "$safe" "$crystal" 90 4096 build "$source" --prelude=empty "${link_flags[@]}" -o "$binary" ;;
    lazy) "$safe" "$adamas" 90 4096 "$source" --no-prelude --no-ast-cache --no-llvm-cache -o "$binary" ;;
    eager) ADAMAS_EAGER_HIR=1 "$safe" "$adamas" 90 4096 "$source" --no-prelude --no-ast-cache --no-llvm-cache -o "$binary" ;;
  esac
}

for mode in crystal lazy eager; do
  compile "$mode" positive.cr "$work/positive" >compile.log 2>&1 || { cat compile.log >&2; exit 1; }
  "$safe" "$work/positive" 5 512
  for negative in unbound reassigned; do
    code=0
    compile "$mode" "$negative.cr" "$work/$negative" >compile.log 2>&1 || code=$?
    if [[ "$code" != 1 ]] || ! grep -Eq 'argument.*Slice\(UInt8\)|no overload matches.*exact' compile.log; then
      echo "$mode did not reject $negative with a source type diagnostic" >&2
      cat compile.log >&2
      exit 1
    fi
  done
  echo "PASS case local binding ($mode)"
done
