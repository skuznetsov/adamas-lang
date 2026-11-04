#!/usr/bin/env bash
# Materializing a structural receiver's positional overload preserves its named siblings.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-named-tuple-source-overload.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

cat >"$work/defs.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

struct NamedTuple
  def attach(metadata : NamedTuple)
    attach(**metadata)
  end

  def attach(**metadata)
    {base: self[:base], supplied: metadata[:value]}
  end

  def choose(input : NamedTuple)
    input[:value]
  end

  def choose(*, value : Int64)
    {base: self[:base], supplied: value}
  end
end
CR

cat "$work/defs.cr" >"$work/pass.cr"
cat >>"$work/pass.cr" <<'CR'
one = {base: 7}
first = one.attach({value: 11})
second = one.attach(value: 13_i64)
selected = one.choose({value: 5})
named = one.choose(value: 19_i64)

two = {base: 'A'}
third = two.attach(value: true)
fourth = two.attach({value: 17_i64})
LibC.exit(first[:base] == 7 && first[:supplied] == 11 &&
  second[:base] == 7 && second[:supplied] == 13_i64 &&
  selected == 5 && named[:base] == 7 && named[:supplied] == 19_i64 &&
  third[:base] == 'A' && third[:supplied] && fourth[:base] == 'A' &&
  fourth[:supplied] == 17_i64 ? 0 : 1)
CR

for rejection in wrong_type wrong_label; do
  cat "$work/defs.cr" >"$work/$rejection.cr"
  cat >>"$work/$rejection.cr" <<'CR'
receiver = {base: 7}
receiver.choose({value: 11})
CR
done
echo 'receiver.choose(value: false)' >>"$work/wrong_type.cr"
echo 'receiver.choose(wrong: 13_i64)' >>"$work/wrong_label.cr"

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
  for fixture in pass wrong_type wrong_label; do
    output="$work/$mode.$fixture"
    status=0
    "${compile[@]}" --no-debug "$work/$fixture.cr" -o "$output" >"$output.log" 2>&1 || status=$?
    if [[ "$fixture" == pass ]]; then
      if [[ "$status" != 0 ]]; then
        cat "$output.log" >&2
        exit 1
      fi
      if ! "$safe" "$output" 5 512 >"$output.run.log" 2>&1; then
        cat "$output.run.log" >&2
        exit 1
      fi
    elif [[ "$status" != 1 ]] ||
         ! grep -Eiq '^error: (no overload matches|missing argument|no argument named|unknown named argument)' "$output.log"; then
      cat "$output.log" >&2
      exit 1
    fi
    printf 'PASS[%s] %s\n' "$mode" "$fixture"
  done
done
