#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures/union_receiver_argument_kind"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
SAFE="$ROOT/scripts/run_safe.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-union-arg-kind.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1
export CRYSTAL_CACHE_DIR="$WORK/cache"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

compile() {
  local compiler="$1" name="$2" out="$3"
  if [[ "$compiler" == stock ]]; then
    "$SAFE" "$CRYSTAL" 90 4096 build --prelude=empty "$FIXTURES/$name.cr" -o "$out"
  else
    "$SAFE" "$ADAMAS" 90 4096 --no-prelude --no-ast-cache --no-llvm-cache "$FIXTURES/$name.cr" -o "$out"
  fi
}

for compiler in stock adamas; do
  for name in order reverse inherited inherited_self result_type mixed_result; do
    out="$WORK/$compiler-$name"
    if ! compile "$compiler" "$name" "$out" >"$out.log" 2>&1; then
      cat "$out.log" >&2
      exit 1
    fi
    "$SAFE" "$out" 5 512 >"$out.stdout"
    case "$name" in
      order) expected=ABDC ;;
      reverse) expected=DCAB ;;
      inherited) expected=EFBA ;;
      inherited_self) expected=EFA ;;
      result_type) expected=ABDC ;;
      mixed_result) expected=ABCD ;;
    esac
    diff -u <(printf '%s\n' "$expected") "$out.stdout"
  done

  for name in wrong_type missing_kind; do
    out="$WORK/$compiler-$name"
    rc=0
    compile "$compiler" "$name" "$out" >"$out.log" 2>&1 || rc=$?
    if [[ "$rc" != 1 ]] || ! grep -Eiq '(argument|overload).*(Bool|KindToken)|InstanceOnlyRoute#emit' "$out.log"; then
      cat "$out.log" >&2
      echo "Expected $compiler to reject $name at the method call (exit $rc)" >&2
      exit 1
    fi
  done
done
echo 'PASS union receiver dispatch preserves source argument kinds'
