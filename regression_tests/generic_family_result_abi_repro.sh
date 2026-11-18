#!/usr/bin/env bash
# A bare generic return restriction can admit multiple physical layouts.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/generic-family-result.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/valid.cr" <<'CR'
lib LibC
  fun putchar(x : Int32) : Int32
end

class Packet(T)
  def initialize(@payload : T)
  end
  def payload : T
    @payload
  end
end

class Factory
  def packet(first) : Packet
    Packet(Int32).new(first)
  end
  def packet(first, second) : Packet
    Packet(Char).new(second)
  end
end

def take(packet : Packet(Int32))
  packet.payload
end

def take_char(packet : Packet(Char))
  packet.payload.ord
end

factory = Factory.new
LibC.putchar(take(factory.packet(65)))
LibC.putchar(take_char(factory.packet(0, 'B')))
LibC.putchar(10)

struct Envelope(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end

def top_pick(flag : Bool) : Envelope
  return Envelope(Int32).new(65) if flag
  Envelope(Char).new('B')
end

module FactoryPair
  def self.pick(flag : Bool) : Envelope
    return Envelope(Char).new('D') unless flag
    Envelope(Int32).new(67)
  end
end

def consume(value : Envelope(Int32))
  LibC.putchar(value.value)
end

def consume(value : Envelope(Char))
  LibC.putchar(value.value.ord)
end

consume(top_pick(true))
consume(top_pick(false))
consume(FactoryPair.pick(true))
consume(FactoryPair.pick(false))
LibC.putchar(10)
CR
printf 'AB\nABCD\n' > "$work/expected"

for tool in stock candidate; do
  if [[ "$tool" == stock ]]; then
    compile=("$safe" "$stock" 120 4096 build --prelude=empty "${link[@]}")
  else
    compile=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  if ! "${compile[@]}" "$work/valid.cr" -o "$work/$tool" > "$work/build.log" 2>&1; then
    cat "$work/build.log" >&2
    exit 1
  fi
  "$safe" "$work/$tool" 10 512 > "$work/output"
  cmp "$work/expected" "$work/output"

  for value in 41 'Envelope(Int32)'; do
    cat > "$work/invalid.cr" <<CR
struct Envelope(T)
end
def wrong : Envelope
  $value
end
wrong
CR
    if "${compile[@]}" "$work/invalid.cr" -o "$work/invalid" > "$work/reject.log" 2>&1; then
      echo "$tool accepted invalid return $value" >&2
      exit 1
    fi
    type=Int32
    [[ "$value" == 41 ]] || type='Envelope(Int32).class'
    if ! grep -Fq 'must return Envelope' "$work/reject.log" || ! grep -Fq "returning $type" "$work/reject.log"; then
      cat "$work/reject.log" >&2
      exit 1
    fi
  done
  echo "$tool passed generic family returns, mixed exits and invalid return kinds"
done
