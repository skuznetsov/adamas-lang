#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/fixtures/named_recursive_struct_result.cr"
enum_fixture="$root/regression_tests/fixtures/named_recursive_enum_result.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/named-recursive-struct.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

sed 's/parse0(code: 67, again: false)/parse0(again: false, code: 67)/' "$fixture" > "$work/formal-order.cr"
sed 's/parse0(code: 67, again: false)/parse0(code: 67)/' "$fixture" > "$work/named-default.cr"
sed 's/parse0(code: 67, again: false)/parse0(false, 67)/' "$fixture" > "$work/positional.cr"
sed 's/parse0(code: 67, again: false)/parse0(other: 67, again: false)/' "$fixture" > "$work/wrong-label.cr"
sed 's/parse0(code: 67, again: false)/parse0(code: 67, again: Bool)/' "$fixture" > "$work/wrong-kind.cr"
sed 's/parse0(code: 67, again: false)/parse0(code: false, again: false)/' "$fixture" > "$work/wrong-type.cr"
# Start the exact body from a named call, with no positional recipe to reuse.
sed 's/parse0(again, 65)/parse0(code: 65, again: again)/' "$fixture" > "$work/named-first.cr"
sed 's/parse0(again, 65)/parse0(again: again)/' "$fixture" > "$work/named-first-default.cr"
sed 's/parse0(again, 65)/parse0(again: again)/' "$work/positional.cr" > "$work/named-first-positional-retry.cr"

# An enum instance, a different enum with the same carrier, and a class
# object have distinct source kinds even when the ABI uses an integer.
sed -e '/^class SmallParser/i\
enum OtherMode\
  Named\
  Base\
end\
' -e 's/mode: Mode::Base/mode: OtherMode::Base/' "$enum_fixture" > "$work/wrong-enum.cr"
sed 's/mode: Mode::Base/mode: Mode/' "$enum_fixture" > "$work/wrong-enum-kind.cr"
printf 'ABC\n' > "$work/expected"

for mode in stock candidate; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  for source in "$fixture" "$work/formal-order.cr" "$work/named-default.cr" "$work/positional.cr" \
                "$work/named-first.cr" "$work/named-first-default.cr" \
                "$work/named-first-positional-retry.cr" "$enum_fixture"; do
    program="$work/$mode-${source##*/}.bin"
    "${build[@]}" "$source" -o "$program" > "$work/build.log" 2>&1 ||
      { cat "$work/build.log" >&2; exit 1; }
    "$safe" "$program" 5 512 > "$work/stdout" 2> "$work/run.log" ||
      { cat "$work/run.log" >&2; exit 1; }
    cmp "$work/expected" "$work/stdout"
  done

  for invalid in wrong-label wrong-kind wrong-type wrong-enum wrong-enum-kind; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/$invalid" > "$work/build.log" 2>&1 ||
       [[ -e "$work/$invalid" ]]; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    if [[ "$mode" == candidate ]]; then
      diagnostic='no overload matches SmallParser#parse0'
    else
      case "$invalid" in
        wrong-label) diagnostic="no parameter named 'other'" ;;
        wrong-kind)  diagnostic="expected argument 'again'.*Bool.class" ;;
        wrong-type)      diagnostic="expected argument 'code'.*Int32, not Bool" ;;
        wrong-enum)      diagnostic="expected argument 'mode'.*OtherMode" ;;
        wrong-enum-kind) diagnostic="expected argument 'mode'.*Mode.class" ;;
      esac
    fi
    grep -Eq "$diagnostic" "$work/build.log" || { cat "$work/build.log" >&2; exit 1; }
  done
  echo "$mode passed named recursive struct calls and invalid-source controls"
done
