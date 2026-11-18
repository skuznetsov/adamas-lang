#!/usr/bin/env bash
# An Enum.new result and its ordinal have distinct source identities.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/enum-construction.XXXXXX")"
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

module Token
  enum Kind
    A
    B
  end

  enum Other
    A
    B
  end

  class Lexer
    def branch(n : Int32) : Kind?
      if n < 0
        nil
      else
        Kind.new(n)
      end
    end

    def early(n : Int32) : Kind?
      return nil if n < 0
      Kind.new(n)
    end
  end
end

def show(k : Token::Kind?)
  if k.is_a?(Token::Kind)
    LibC.putchar(65 &+ k.value)
  else
    LibC.putchar(78)
  end
end

def tag(x : Int32)
  LibC.putchar(73)
end
def tag(x : Token::Kind)
  LibC.putchar(75)
end
def tag(x : Token::Other)
  LibC.putchar(79)
end

def reuse(n : Int32)
  first = Token::Kind.new(n)
  second = Token::Other.new(n)
  tag(first)
  tag(second)
  tag(n)
  tag(first.value)
end

lexer = Token::Lexer.new
show(lexer.branch(-1))
show(lexer.branch(1))
show(lexer.early(-1))
show(lexer.early(1))
reuse(1)
LibC.putchar(10)
CR
printf 'NBNBKOII\n' > "$work/expected"

for tool in stock candidate; do
  if [[ "$tool" == stock ]]; then
    build=("$safe" "$stock" 120 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$work/valid.cr" -o "$work/program"
  "$safe" "$work/program" 8 512 > "$work/actual"
  cmp "$work/expected" "$work/actual"

  for value in n Kind; do
    cat > "$work/invalid.cr" <<CR
enum Kind
  A
end
def wrong(n : Int32) : Kind?
  n < 0 ? nil : $value
end
wrong(0)
CR
    if "${build[@]}" "$work/invalid.cr" -o "$work/invalid" > "$work/reject.log" 2>&1; then
      echo "$tool accepted an invalid return of $value" >&2
      exit 1
    fi
    expected=Int32
    if [[ "$value" == Kind ]]; then expected=Kind.class; fi
    grep -E 'must return.*Kind.*returning' "$work/reject.log" | grep -F "$expected"
  done
  echo "$tool passed enum construction and source identity controls"
done
