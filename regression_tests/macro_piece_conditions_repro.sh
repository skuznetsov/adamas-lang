#!/usr/bin/env bash
# A condition inside a macro literal sees the bindings of its enclosing loop.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-macro-piece-conditions.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

cat >"$work/scoped.cr" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
end

def example
  {% begin %}
    {% for n in [0, 1, 2] %}
      {% if n == 0 %}
        LibC.putchar(65)
      {% elsif n == 1 %}
        LibC.putchar(66)
      {% else %}
        LibC.putchar(67)
      {% end %}
    {% end %}
  {% end %}
end

example
LibC.putchar(10)
CR

cat >"$work/keys.cr" <<'CR'
require "named_tuple"

lib LibC
  fun putchar(value : Int32) : Int32
end

struct NamedTuple
  def show_keys
    {% begin %}
      {% for key in T %}
        {% if T.keys.includes?(key) && key != "skip".id %}
          LibC.putchar(self[{{key.symbolize}}])
        {% end %}
      {% end %}
    {% end %}
  end
end

{first: 65, skip: 88, last: 66}.show_keys
LibC.putchar(10)
CR

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    link=()
    [[ "$(uname -s)" != Darwin ]] || link=(--link-flags=-fuse-ld=/usr/bin/ld)
    compile=("$safe" "$original" 30 1024 build --prelude=empty --no-color "${link[@]}")
  else
    eager_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" != eager ]] || eager_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${eager_env[@]}" "$safe" "$candidate" 30 1024 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  for fixture in scoped keys; do
    output="$work/$mode.$fixture"
    if ! "${compile[@]}" --no-debug "$work/$fixture.cr" -o "$output" >"$output.log" 2>&1; then
      cat "$output.log" >&2
      exit 1
    fi
    "$safe" "$output" 5 512 >"$output.run.log" 2>&1
    case "$fixture" in
      scoped) expected=ABC ;;
      keys) expected=AB ;;
    esac
    actual="$(awk '/^=== STDOUT ===$/{capture=1;next} /^=== STDERR ===$/{capture=0} capture' "$output.run.log")"
    if [[ "$actual" != "$expected" ]]; then
      cat "$output.run.log" >&2
      exit 1
    fi
    printf 'PASS[%s] %s\n' "$mode" "$fixture"
  done
done
