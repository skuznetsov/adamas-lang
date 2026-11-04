#!/usr/bin/env bash
# Exact keyword-rest layouts must reach source formals and their consumers.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-typed-keyword-rest.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

cat >"$work/direct.cr" <<'CR'
require "named_tuple"

lib LibC
  fun putchar(value : Int32) : Int32
end

raw = NamedTuple.new(first: 65, second: 66_i64)
LibC.putchar(raw[:first])
LibC.putchar(raw[:second] == 66_i64 ? 66 : 88)

LibC.putchar(10)
CR

cat >"$work/values.cr" <<'CR'
require "named_tuple"

lib LibC
  fun putchar(value : Int32) : Int32
end

def identity(**entries : **U) : U forall U
  entries
end

struct Pack
  def take(**entries : **U) : U forall U
    entries
  end
end

left = {keep: 65, overwrite: false}
merged = left.merge({overwrite: 66, extra: 67_i64})
named = left.merge(overwrite: 68, extra: 69_i64)
packed = identity(char: 70, number: 71_i64)
taken = Pack.new.take(char: 72, number: 73_i64)

LibC.putchar(merged[:keep])
LibC.putchar(merged[:overwrite])
LibC.putchar(merged[:extra] == 67_i64 ? 67 : 88)
LibC.putchar(named[:overwrite])
LibC.putchar(named[:extra] == 69_i64 ? 69 : 88)
LibC.putchar(packed[:char])
LibC.putchar(packed[:number] == 71_i64 ? 71 : 88)
LibC.putchar(taken[:char])
LibC.putchar(taken[:number] == 73_i64 ? 73 : 88)

LibC.putchar(10)
CR

cat >"$work/overload.cr" <<'CR'
require "named_tuple"
lib LibC
  fun putchar(value : Int32) : Int32
end
struct NamedTuple
  def package(input : NamedTuple)
    {tag: 65}
  end
  def package(**input : **U) forall U
    {tag: input[:tag]}
  end
end
n = {tag: 66}
LibC.putchar(n.package({tag: 88})[:tag])
LibC.putchar(n.package(tag: 66)[:tag])
LibC.putchar(10)
CR

cat >"$work/neg_label.cr" <<'CR'
require "named_tuple"
def pack(**entries : **U) forall U
  entries
end
pack(key: false)[:typo]
CR

cat >"$work/neg_type.cr" <<'CR'
require "named_tuple"
def pack(**entries : **U) forall U
  entries
end
def need(value : Int32)
  value
end
need(pack(key: false)[:key])
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
  for fixture in direct values overload neg_label neg_type; do
    output="$work/$mode.$fixture"
    status=0
    "${compile[@]}" --no-debug "$work/$fixture.cr" -o "$output" >"$output.log" 2>&1 || status=$?
    case "$fixture" in
      direct|overload) expected=AB ;;
      values) expected=ABCDEFGHI ;;
      neg_label) error="missing key 'typo' for named tuple NamedTuple\(key: Bool\)" ;;
      neg_type) error="Int32.*Bool" ;;
    esac
    if [[ "$fixture" == neg_* ]]; then
      if [[ "$status" != 1 ]] || ! grep -Eiq "^error: .*$error" "$output.log"; then
        cat "$output.log" >&2
        exit 1
      fi
    else
      if [[ "$status" != 0 ]] || ! "$safe" "$output" 5 512 >"$output.run.log" 2>&1; then
        cat "$output.log" >&2
        [[ ! -f "$output.run.log" ]] || cat "$output.run.log" >&2
        exit 1
      fi
      actual="$(awk '/^=== STDOUT ===$/{show=1; next} /^=== STDERR ===$/{show=0} show' "$output.run.log")"
      if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL[%s] %s expected %s, got %s\n' "$mode" "$fixture" "$expected" "$actual" >&2
        exit 1
      fi
    fi
    printf 'PASS[%s] %s\n' "$mode" "$fixture"
  done
done
