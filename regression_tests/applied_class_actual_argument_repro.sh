#!/usr/bin/env bash
# An applied class restriction admits a concrete argument whose type and
# element layout must reach the specialized body.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/applied-class-actual.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat > "$work/rows.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

module Sortable
end

class Channel
  include Sortable

  def details : Int32
    67
  end
end

class Other
  include Sortable

  def details : String
    "O"
  end
end

class Rows(T)
  @first : T

  def initialize(@first : T)
  end

  def visit(&)
    yield @first
  end
end

def consume(value : Int32) : Int32
  LibC.putchar(value)
end

def page(items : Rows(Sortable)) : Int32
  consume(items.visit { |item| item.details })
end

page(Rows(Channel).new(Channel.new))
CRYSTAL

sed 's/Rows/Array/g' "$work/rows.cr" > "$work/array.cr"
sed -e 's/class Rows(T)/class Hash(K, V)/' -e 's/ : T/ : V/g' -e 's/Rows(/Hash(Int32, /g' \
  "$work/rows.cr" > "$work/hash.cr"
sed 's/Hash(Int32, Channel)/Hash(String, Channel)/' "$work/hash.cr" > "$work/wrong-key.cr"
sed 's/  include Sortable/  # Unrelated class/' "$work/rows.cr" > "$work/unrelated.cr"
sed 's/page(Rows(Channel).new(Channel.new))/page(Rows(Other).new(Other.new))/' \
  "$work/rows.cr" > "$work/wrong-result.cr"
cat "$work/rows.cr" > "$work/two-instances.cr"
cat >> "$work/two-instances.cr" <<'CRYSTAL'
def consume(value : String) : Int32
  LibC.putchar(79)
end

page(Rows(Other).new(Other.new))
CRYSTAL

for mode in stock lazy eager; do
  case "$mode" in
    stock) compile=("$safe" "$original" 20 512 build --prelude=empty "${stock_link[@]}") ;;
    lazy) compile=(env -u ADAMAS_EAGER_MONO -u ADAMAS_EAGER_HIR "$safe" "$candidate" 20 512 --no-prelude) ;;
    eager) compile=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 20 512 --no-prelude) ;;
  esac

  for name in rows array hash two-instances unrelated wrong-key wrong-result; do
    log="$work/$mode.$name.log"
    binary="$work/$mode.$name"
    case "$name" in
      unrelated|wrong-key) diagnostic='expected argument.*page|no overload matches page' ;;
      wrong-result) diagnostic='expected argument.*consume|no overload matches consume.*\(String\)' ;;
      *) diagnostic='' ;;
    esac
    if [[ -n "$diagnostic" ]]; then
      if "${compile[@]}" "$work/$name.cr" -o "$binary" > "$log" 2>&1 ||
         ! grep -q '^\[EXIT: 1\]' "$log" || ! grep -Eq "$diagnostic" "$log"; then
        cat "$log" >&2
        exit 1
      fi
    else
      expected=C
      [[ "$name" == two-instances ]] && expected=CO
      if ! "${compile[@]}" "$work/$name.cr" -o "$binary" > "$log" 2>&1 ||
         ! "$safe" "$binary" 5 512 >> "$log" 2>&1 ||
         ! grep -q "^${expected}=== STDERR ===$" "$log"; then
        cat "$log" >&2
        exit 1
      fi
    fi
    printf 'PASS: %s %s\n' "$mode" "$name"
  done
done
