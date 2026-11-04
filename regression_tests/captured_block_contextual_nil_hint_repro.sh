#!/usr/bin/env bash
# The enclosing method's Nil return hint cannot erase a captured block result.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-block-nil-hint.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/source.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

struct Relay(T)
  alias Callback = Proc(Int32, Int32, Nil)

  def initialize(@left : T, @right : T)
  end

  def pick(&block : T, T -> R) : R forall R
    invoke(block)
  end

  def invoke(callback)
    callback.call(@left, @right)
  end

  def discard(&block : T, T -> Nil) : Nil
    callback_result = block.call(@left, @right)
    check_discarded(callback_result)
  end

  def check_discarded(value : Nil) : Nil
    LibC.putchar(66)
  end

  def discard_alias(&block : Callback) : Nil
    result = block.call(3, 2)
    check_discarded(result)
  end
end

def in_nil_method : Nil
  relay = Relay(Int32).new(3, 2)
  LibC.putchar(relay.pick { |a, b| a > b ? 65 : 88 })
  relay.discard { |a, b| a > b ? 67 : 89 }
  relay.discard_alias { |a, b| a > b ? 67 : 89 }
  LibC.putchar(10)
end

in_nil_method
CRYSTAL

"$safe" "$original" 30 3072 build --prelude=empty --single-module --no-debug \
  "${stock_link[@]}" "$work/source.cr" -o "$work/stock" >"$work/stock.log" 2>&1 || {
  cat "$work/stock.log" >&2
  exit 1
}
"$safe" "$candidate" 30 3072 --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
  "$work/source.cr" -o "$work/adamas" >"$work/adamas.log" 2>&1 || {
  cat "$work/adamas.log" >&2
  exit 1
}
printf 'ABB\n' >"$work/expected"
for executable in "$work/stock" "$work/adamas"; do
  "$safe" "$executable" 5 512 >"$executable.stdout"
  diff -u "$work/expected" "$executable.stdout"
done
printf 'PASS: contextual Nil hint preserves the result and explicit Nil discards it\n'
