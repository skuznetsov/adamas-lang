#!/usr/bin/env bash
# A bare generic arm restricts source overloads without defining an ABI.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-allocator-bare-union.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/table.cr" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
end

class Table
  @marker : Int32

  def marker : Int32
    @marker
  end

  def initialize(bytes : UInt8? = nil)
    @marker = 68
  end

  def initialize(properties : NamedTuple | Int32)
    @marker = if properties.is_a?(Int32)
                properties
              else
                properties[:product]
              end
  end
end
CR
cat >"$work/accepted.cr" <<'CR'
require "./table"

PROPERTIES = Table.new({product: 65, capabilities: {enabled: true}})
LibC.putchar(PROPERTIES.marker)
LibC.putchar(Table.new({product: 66}).marker)
LibC.putchar(Table.new(67).marker)
LibC.putchar(Table.new.marker)
LibC.putchar(Table.new(7_u8).marker)
LibC.putchar(Table.new(properties: {product: 69, flags: {1, 2}}).marker)

def argument(flag : Bool)
  LibC.putchar(46)
  flag ? {product: 70} : 71
end

def emit(flag : Bool)
  LibC.putchar(Table.new(argument(flag)).marker)
end

emit(true)
emit(false)
CR
printf 'ABCDDE.F.G' >"$work/expected"

cat >"$work/rejecting_table.cr" <<'CR'
class Table
  def initialize(bytes : UInt8? = nil)
  end

  def initialize(properties : NamedTuple | Int32)
  end
end
CR
cat >"$work/rejected_scalar.cr" <<'CR'
require "./rejecting_table"
Table.new(false)
CR
cat >"$work/rejected_union.cr" <<'CR'
require "./rejecting_table"
def make(flag : Bool)
  Table.new(flag ? {product: 65} : false)
end
make(true)
CR
cat >"$work/rejected_key.cr" <<'CR'
require "./table"
Table.new({missing: 65})
CR

check() {
  local compiler="$1" mode="$2" status=0
  local output="$work/$compiler.$mode"
  local command=() diagnostic
  if [[ "$compiler" == crystal ]]; then
    command=("$original" 60 4096 build --prelude=empty --no-color "${stock_link[@]}")
    diagnostic="can't use NamedTuple"
  else
    command=("$candidate" 60 4096 --no-prelude --no-ast-cache --no-llvm-cache)
    diagnostic='no overload matches Table\.new.*Bool'
  fi
  if [[ "$mode" == rejected_key ]]; then
    diagnostic="missing key 'product'"
  fi
  "$safe" "${command[@]}" --no-debug "$work/$mode.cr" -o "$output" >"$output.compile.log" 2>&1 || status=$?
  if [[ "$mode" == accepted ]]; then
    if [[ "$status" != 0 ]]; then
      cat "$output.compile.log" >&2
      return 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$safe" "$output" 5 512 >"$output.stdout" 2>"$output.run.log" || {
      cat "$output.run.log" >&2
      return 1
    }
    cmp "$work/expected" "$output.stdout"
  elif [[ "$status" != 1 || -e "$output" ]] || ! grep -Eq "$diagnostic" "$output.compile.log"; then
    cat "$output.compile.log" >&2
    return 1
  fi
  printf 'PASS[%s] %s\n' "$compiler" "$mode"
}

for mode in accepted rejected_scalar rejected_union rejected_key; do
  check crystal "$mode"
  (unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO; check lazy "$mode")
  (unset ADAMAS_EAGER_HIR; export ADAMAS_EAGER_MONO=1; check eager "$mode")
done
