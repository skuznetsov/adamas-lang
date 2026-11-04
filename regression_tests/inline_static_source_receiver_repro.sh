#!/usr/bin/env bash
# A selected template body must see the applied class receiver at each call.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inline-static.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/receiver.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

class Decode(T)
end

def Decode.with_receiver(seed : Int32, &)
  forward(seed) { |receiver| yield receiver }
end

def Decode.forward(seed : Int32, &)
  yield self
end

def emit(owner : Decode(Int32).class)
  LibC.putchar(65)
end

def emit(owner : Decode(Char).class)
  LibC.putchar(66)
end

class Element(T)
  def initialize(seed : Int32)
  end
end

class Source(T)
  def self.forward(seed : Int32, &)
    yield self, T.new(seed)
  end
end

class Derived(T) < Source(Element(T))
end

def emit(owner : Derived(Char).class, value : Element(Char))
  LibC.putchar(67)
end

Decode(Int32).with_receiver(1) { |owner| emit(owner) }
Decode(Char).with_receiver(1) { |owner| emit(owner) }
Derived(Char).forward(1) { |owner, element| emit(owner, element) }
LibC.putchar(10)
CRYSTAL
printf 'ABC\n' >"$work/expected"

cat >"$work/wrong_constructor.cr" <<'CRYSTAL'
class Token
end

class Numeric
  def initialize(number : Int32)
  end
end

class Decode(T)
end

def Decode.with_element(token : Token, &)
  new(token) { |element| yield element }
end

def Decode.new(token : Token, &)
  yield T.new(token)
end

Decode(Numeric).with_element(Token.new) { |element| element }
CRYSTAL

compile() {
  local mode="$1" input="$2" output="$3"
  if [[ "$mode" == original ]]; then
    "$safe" "$original" 40 3072 build "$input" --prelude=empty --single-module --no-debug "${stock_link[@]}" -o "$output"
  else
    local eager=0
    if [[ "$mode" == eager ]]; then eager=1; fi
    ADAMAS_EAGER_HIR="$eager" ADAMAS_EAGER_MONO="$eager" \
      "$safe" "$candidate" 40 3072 "$input" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output"
  fi
}

for mode in original lazy eager; do
  output="$work/receiver.$mode"
  if ! compile "$mode" "$work/receiver.cr" "$output" >"$output.compile.log" 2>&1; then
    cat "$output.compile.log" >&2
    exit 1
  fi
  if ! "$safe" "$output" 5 512 >"$output.stdout" 2>"$output.stderr"; then
    cat "$output.stderr" >&2
    exit 1
  fi
  diff -u "$work/expected" "$output.stdout"

  code=0
  compile "$mode" "$work/wrong_constructor.cr" "$work/invalid" >"$output.invalid.log" 2>&1 || code=$?
  if [[ "$code" != 1 ]] || ! grep -Eq 'Numeric.*new.*Token|Numeric.*initialize.*Token' "$output.invalid.log"; then
    cat "$output.invalid.log" >&2
    exit 1
  fi
  printf 'PASS inline static source receiver (%s)\n' "$mode"
done
