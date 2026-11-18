#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${ADAMAS_BIN:-${1:-$root/bin/adamas}}"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-forward-proc.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1

cat >"$work/pass.cr" <<'CR'
@[Link("c")]
lib Output
  fun putchar(c : Int32) : Int32
end

struct Proc(*T, R)
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end

def invoke(&)
  yield
end

def invoke_value(&)
  yield 66
end

invoke(&->{ Output.putchar(65) })
invoke_value(&->(n : Int32) { Output.putchar(n) })
invoke(&(->{ Output.putchar(67) }))
invoke &->{ Output.putchar(68) }
Output.putchar(10)
CR

"$safe" "$stock" 90 4096 build --prelude=empty "$work/pass.cr" -o "$work/stock"
"$safe" "$compiler" 90 4096 --no-prelude --no-ast-cache --no-llvm-cache "$work/pass.cr" -o "$work/adamas"
for name in stock adamas; do
  "$safe" "$work/$name" 5 512 >"$work/$name.out"
done
printf 'ABCD\n' >"$work/expected"
cmp "$work/expected" "$work/stock.out"
cmp "$work/stock.out" "$work/adamas.out"

cat >"$work/separated.cr" <<'CR'
def invoke(&)
  yield
end
invoke(& ->{})
CR
for name in stock adamas; do
  if [[ "$name" == stock ]]; then
    command=("$safe" "$stock" 90 4096 build --prelude=empty)
  else
    command=("$safe" "$compiler" 90 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  status=0
  "${command[@]}" "$work/separated.cr" -o "$work/bad" >"$work/error" 2>&1 || status=$?
  if [[ "$status" != 1 ]] || ! grep -Eiq 'unterminated|unexpected|expected|syntax|parse error' "$work/error"; then
    cat "$work/error" >&2
    echo "Expected $name to reject a separated block-pass ampersand" >&2
    exit 1
  fi
done

echo "PASS forwarded proc arrows preserve arguments and invocation order"
