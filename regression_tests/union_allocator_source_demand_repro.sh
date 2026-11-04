#!/usr/bin/env bash
# A union constructor can demand its initializer-backed arm before any scalar call.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-union-allocator.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/accepted.cr" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

class Text; end
class Packet; end

class Buffer
  @size : Int32

  def size : Int32
    @size
  end

  private def default_writable : Bool
    LibC.putchar(68)
    true
  end

  def initialize(packet : Packet, writable = default_writable)
    @size = writable ? 2 : 4
  end

  def self.new(text : Text) : self
    new(Packet.new, false)
  end
end

def with_value(value, &)
  yield value
end

def check(flag : Bool)
  value = flag ? Text.new : Packet.new
  with_value(value) { |v| Buffer.new(v).size }
end

LibC.exit(1) unless check(true) == 4
LibC.exit(2) unless check(false) == 2
CR
sed 's/flag ? Text.new : Packet.new/flag ? Text.new : false/' "$work/accepted.cr" >"$work/rejected.cr"
printf D >"$work/expected"

check() {
  local compiler="$1" mode="$2" status=0
  local output="$work/$compiler.$mode"
  local command=()
  if [[ "$compiler" == crystal ]]; then
    command=("$original" 60 4096 build --prelude=empty --no-color "${stock_link[@]}")
  else
    command=("$candidate" 60 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi

  "$safe" "${command[@]}" --no-debug "$work/$mode.cr" -o "$output" >"$output.compile.log" 2>&1 || status=$?
  if [[ "$mode" == rejected ]]; then
    if [[ "$status" != 1 || -e "$output" ]] || ! grep -Eq 'Buffer\.new.*Bool' "$output.compile.log"; then
      cat "$output.compile.log" >&2
      return 1
    fi
  else
    if [[ "$status" != 0 ]]; then
      cat "$output.compile.log" >&2
      return 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$safe" "$output" 5 512 >"$output.stdout" 2>"$output.run.log" || {
      cat "$output.run.log" >&2
      return 1
    }
    cmp "$work/expected" "$output.stdout"
  fi
  printf 'PASS[%s] %s\n' "$compiler" "$mode"
}

for mode in accepted rejected; do
  check crystal "$mode"
  check adamas "$mode"
done
