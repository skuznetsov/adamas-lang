#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${ADAMAS_BIN:-${1:-$root/bin/adamas}}"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-enum-operand.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1

src="$root/regression_tests/enum_call_operand.cr"
for expression in "65" "Other::Public"; do
  if [[ "$expression" == 65 ]]; then name=integer; else name=foreign; fi
  cat "$src" >"$work/$name.cr"
  cat >>"$work/$name.cr" <<'CR'
enum Other
  Public = 65
end
CR
  printf 'Parser.new.accept(false, %s)\n' "$expression" >>"$work/$name.cr"
done

for kind in stock adamas; do
  if [[ "$kind" == stock ]]; then
    command=("$safe" "$stock" 90 4096 build --prelude=empty)
  else
    command=("$safe" "$compiler" 90 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${command[@]}" "$src" -o "$work/$kind"
  "$safe" "$work/$kind" 5 512 >"$work/$kind.out"
  for name in integer foreign; do
    status=0
    "${command[@]}" "$work/$name.cr" -o "$work/bad" >"$work/error" 2>&1 || status=$?
    if [[ "$status" != 1 ]] || ! grep -Eiq 'argument|overload|expected.*Visibility' "$work/error"; then
      cat "$work/error" >&2
      echo "Expected $kind to reject $name as a Visibility argument" >&2
      exit 1
    fi
  done
done
printf 'AB\n' >"$work/expected"
cmp "$work/expected" "$work/stock.out"
cmp "$work/stock.out" "$work/adamas.out"
echo "PASS valid and rejected enum call arguments match Crystal"
