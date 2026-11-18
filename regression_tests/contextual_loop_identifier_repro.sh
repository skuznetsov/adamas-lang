#!/usr/bin/env bash
# A blockless loop may be a local or a regular method, including in arguments.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${ADAMAS_BIN:-${1:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/contextual-loop.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
source="$root/regression_tests/fixtures/contextual_loop_identifier.cr"

cat > "$work/reject.cr" <<'CRYSTAL'
def only_int(value : Int32)
  value
end

def probe(loop : String)
  only_int(loop)
end

probe("wrong")
CRYSTAL

export RUN_SAFE_PASSTHROUGH_STDIO=1
printf 'ABCDEFG\n' > "$work/expected"
for mode in original candidate; do
  if [[ "$mode" == original ]]; then
    compiler=("$original" 120 2048 build --prelude=empty)
    if [[ "$(uname -s)" == Darwin ]]; then
      compiler+=(--link-flags=-fuse-ld=/usr/bin/ld)
    fi
  else
    compiler=("$candidate" 120 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "$safe" "${compiler[@]}" "$source" -o "$work/$mode" > "$work/$mode.log" 2>&1 || { cat "$work/$mode.log" >&2; exit 1; }
  "$safe" "$work/$mode" 5 512 > "$work/$mode.out" 2> "$work/$mode.run" || { cat "$work/$mode.run" >&2; exit 1; }
  cmp "$work/expected" "$work/$mode.out"
  result=0
  "$safe" "${compiler[@]}" "$work/reject.cr" -o "$work/reject" > "$work/$mode.reject" 2>&1 || result=$?
  if [[ $result != 1 ]] || ! rg -qi '(argument|overload).*only_int.*String' "$work/$mode.reject"; then
    cat "$work/$mode.reject" >&2
    exit 1
  fi
  echo "PASS $mode: local, receiver, assignment, method calls, both block forms, and String rejection"
done
