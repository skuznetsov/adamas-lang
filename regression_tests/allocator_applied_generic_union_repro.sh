#!/usr/bin/env bash
# A source-admitted applied generic keeps its concrete initializer ABI.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-applied-union.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/base.cr" <<'CRYSTAL'
lib LibC
  fun getchar : Int32
  fun putchar(value : Int32) : Int32
end

class SourceMap(K, V)
end

class Token
end

class Other
end

class Unrelated
end

class BytesCarrier
end

alias Field = Token | Other

def source_marker(map : SourceMap(Int32, Token))
  65
end

def source_marker(map : SourceMap(Int32, Other))
  67
end

class Table
  @marker : Int32

  def initialize(value : SourceMap(Int32, Field) | NamedTuple)
    @marker = source_marker(value)
  end

  def initialize(value : BytesCarrier? = nil)
    @marker = 66
  end

  def marker : Int32
    @marker
  end
end
CRYSTAL
cp "$work/base.cr" "$work/positive.cr"
cat >>"$work/positive.cr" <<'CRYSTAL'

input = LibC.getchar
value = input == 65 ? SourceMap(Int32, Token).new : nil
LibC.putchar(Table.new(value).marker)
other = input == 67 ? SourceMap(Int32, Other).new : nil
LibC.putchar(Table.new(other).marker)
LibC.putchar(10)
CRYSTAL
cp "$work/base.cr" "$work/negative.cr"
cat >>"$work/negative.cr" <<'CRYSTAL'

value = LibC.getchar == 65 ? SourceMap(Int32, Unrelated).new : nil
Table.new(value)
CRYSTAL

compile() {
  local mode="$1" input="$2" output="$3"
  case "$mode" in
    original)
      "$safe" "$original" 45 3072 build "$input" --prelude=empty --single-module --no-debug "${stock_link[@]}" -o "$output"
      ;;
    lazy)
      env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO \
        "$safe" "$candidate" 45 3072 "$input" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output"
      ;;
    eager)
      ADAMAS_EAGER_MONO=1 \
        "$safe" "$candidate" 45 3072 "$input" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output"
      ;;
  esac
}

for mode in original lazy eager; do
  if ! compile "$mode" "$work/positive.cr" "$work/program" >"$work/compile.log" 2>&1; then
    cat "$work/compile.log" >&2
    exit 1
  fi
  for example in A:AB B:BB C:BC; do
    printf '%s' "${example%:*}" | "$safe" "$work/program" 5 512 >"$work/stdout"
    printf '%s\n' "${example#*:}" >"$work/expected"
    diff -u "$work/expected" "$work/stdout"
  done

  code=0
  compile "$mode" "$work/negative.cr" "$work/rejected" >"$work/rejected.log" 2>&1 || code=$?
  # Stock Crystal can reject the bare NamedTuple alternative while reporting
  # the failed call. Neither compiler may admit the unrelated generic arm.
  if [[ "$code" != 1 ]] || ! rg -q 'no overload matches.*(Table|initialize)|can.t use NamedTuple\(T\) in unions' "$work/rejected.log"; then
    cat "$work/rejected.log" >&2
    exit 1
  fi
  printf 'PASS applied generic constructor union (%s)\n' "$mode"
done
