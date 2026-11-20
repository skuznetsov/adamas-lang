#!/usr/bin/env bash
# Checked fixed-initializer upcasts bind independent forwarded callback outputs.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/nominal_callback_forward_result_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/nominal-callback-forward.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
sed 's/FirstEntry.new(key, checked_entry)/UnrelatedEntry.new(key, checked_entry)/' "$fixture" > "$work/unrelated_cast.cr"
sed 's/FirstEntry.new(key, checked_entry)/WrongEntry.new(key, checked_entry)/' "$fixture" > "$work/wrong_argument.cr"
awk '
  /FirstEntry[.]new\(key, checked_entry\)[.]as\(FirstValue\)/ {
    print "    discarded = FirstEntry.new(key, checked_entry).as(FirstValue)"
    print "    UnrelatedEntry.new(key, checked_entry).as(FirstValue)"
    next
  }
  { print }
' "$fixture" > "$work/discarded_prefix_invalid_tail.cr"
printf 'AAB\n' > "$work/expected"

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
    if [[ "$mode" == eager ]]; then
      build=(env ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1 "${build[@]}")
    fi
  fi
  "${build[@]}" "$fixture" -o "$work/$mode" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/$mode" 5 512 > "$work/$mode.out" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  diff -u "$work/expected" "$work/$mode.out"

  for invalid in unrelated_cast wrong_argument discarded_prefix_invalid_tail; do
    case "$invalid" in
      unrelated_cast|discarded_prefix_invalid_tail)
        diagnostic='(cannot|can.t) cast.*UnrelatedEntry.*FirstValue|FirstValue.*UnrelatedEntry'
        ;;
      wrong_argument)
        diagnostic='no overload matches.*WrongEntry|WrongEntry.*(FirstValue|String)|(FirstValue|String).*WrongEntry'
        ;;
    esac
    if [[ "$mode" != stock ]]; then
      # An unproved forwarded result can fail before the callback body is
      # materialized. Require the exact consumer's result error in that case.
      diagnostic+='|method first_result[$]FirstValue must return ResultBox[(]FirstValue[)], but it is returning Pointer'
    fi
    status=0
    "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1 || status=$?
    if [[ "$status" == 0 || -e "$work/invalid" ]] || ! rg -qi "$diagnostic" "$work/invalid.log"; then
      cat "$work/invalid.log" >&2
      echo "$mode did not report the expected static cast/overload rejection for $invalid" >&2
      exit 1
    fi
  done
  echo "$mode matched both independent callback outputs and rejected invalid casts, arguments, and tainted tails"
done
