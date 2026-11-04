#!/usr/bin/env bash
# Included overloads admit each argument variant, including virtual targets.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/included-union-admission.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat > "$work/virtual.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
end

class Text
end

class Pattern
end

module Search
  def match(value : Text) : Int32
    84
  end

  def match(value : Pattern) : Int32
    80
  end
end

abstract class Client
  include Search
end

class First < Client
  def match(value : Text) : Int32
    65
  end

  def match(value : Pattern) : Int32
    66
  end
end

class Second < Client
  def match(value : Text) : Int32
    67
  end

  def match(value : Pattern) : Int32
    68
  end
end

def check(client : Client, term : Text | Pattern) : Int32
  LibC.putchar(client.match(term))
end

client = LibC.getpid > 0 ? First.new : Second.new
check(client, LibC.getpid > 0 ? Text.new : Pattern.new)
check(client, LibC.getpid < 0 ? Text.new : Pattern.new)

second = LibC.getpid < 0 ? First.new : Second.new
check(second, LibC.getpid > 0 ? Text.new : Pattern.new)
check(second, LibC.getpid < 0 ? Text.new : Pattern.new)
CRYSTAL

# Remove the applicable overload for one arm, including its overrides.
sed 's/match(value : Pattern)/other(value : Pattern)/g' "$work/virtual.cr" > "$work/uncovered.cr"
sed '/^module Search$/,/^abstract class Client$/s/def match(value : Pattern)/private def match(value : Pattern)/' \
  "$work/virtual.cr" > "$work/included-private.cr"
sed '/^class Second < Client$/,$s/def match(value : Pattern)/private def match(value : Pattern)/' \
  "$work/virtual.cr" > "$work/override-private.cr"

for mode in stock lazy eager; do
  case "$mode" in
    stock) compile=("$safe" "$original" 20 512 build --prelude=empty "${stock_link[@]}") ;;
    lazy) compile=(env -u ADAMAS_EAGER_MONO -u ADAMAS_EAGER_HIR "$safe" "$candidate" 20 512 --no-prelude) ;;
    eager) compile=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 20 512 --no-prelude) ;;
  esac

  for name in virtual uncovered included-private override-private; do
    log="$work/$mode.$name.log"
    binary="$work/$mode.$name"
    case "$name" in
      uncovered) diagnostic='expected argument.*match|no overload matches.*match|incompatible explicit arguments.*match' ;;
      *-private) diagnostic="private method 'match' called" ;;
      *) diagnostic='' ;;
    esac
    if [[ "$name" == virtual ]]; then
      if ! "${compile[@]}" "$work/$name.cr" -o "$binary" > "$log" 2>&1 ||
         ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$safe" "$binary" 5 512 > "$binary.stdout" 2>> "$log" ||
         [[ "$(cat "$binary.stdout")" != ABCD ]]; then
        cat "$log" >&2
        exit 1
      fi
    elif "${compile[@]}" "$work/$name.cr" -o "$binary" > "$log" 2>&1 ||
         ! grep -q '^\[EXIT: 1\]' "$log" || ! grep -Eq "$diagnostic" "$log"; then
      cat "$log" >&2
      exit 1
    fi
    printf 'PASS: %s %s\n' "$mode" "$name"
  done
done
