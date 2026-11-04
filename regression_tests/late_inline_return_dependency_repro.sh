#!/usr/bin/env bash
# A late inline force refusal must trigger replay before selecting an overload.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-late-inline-return.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/source.cr" <<'CRYSTAL'
module Action(T)
  def create_context(marker : Int32)
    context = Context.new(marker, self)
    self.wait(context)
    context
  end
end

class Context(T)
  getter marker : Int32

  def initialize(@marker : Int32, @action : Action(T))
  end
end

class Receive(T)
  include Action(T)

  def wait(context : Context(T)) : Nil
  end
end

class Timeout
  include Action(Nil)

  def wait(context : Context(Nil)) : Nil
  end
end

class Consumer
  def self.read(ops, marker)
    contexts = ops.map &.create_context(marker)
    contexts
  end
end

class Entry
  def self.read(ops, marker)
    Consumer.read(ops, marker)
  end
end

def marker(contexts : Tuple(Context(Nil), Context(Nil))) : Int32
  contexts[0].marker
end

def marker(contexts) : Int32
  88
end

puts marker(Entry.read({Receive(Nil).new, Timeout.new}, 65))
CRYSTAL
sed -e 's/^class Consumer$/module Consumer/' -e 's/^class Entry$/module Entry/' \
  "$work/source.cr" >"$work/module.cr"

printf '65\n' >"$work/expected"
for fixture in source module; do
  stock="$work/$fixture.stock"
  adamas="$work/$fixture.adamas"
  "$safe" "$original" 90 4096 build --no-debug --single-module \
    "${stock_link[@]}" "$work/$fixture.cr" -o "$stock" >"$stock.log" 2>&1 || {
    cat "$stock.log" >&2
    exit 1
  }
  "$safe" "$candidate" 90 4096 --no-debug --no-ast-cache --no-llvm-cache \
    "$work/$fixture.cr" -o "$adamas" >"$adamas.log" 2>&1 || {
    cat "$adamas.log" >&2
    exit 1
  }
  for executable in "$stock" "$adamas"; do
    "$safe" "$executable" 5 512 >"$executable.stdout"
    diff -u "$work/expected" "$executable.stdout"
  done
  printf 'PASS: late inline return dependency in %s fixture\n' "$fixture"
done
