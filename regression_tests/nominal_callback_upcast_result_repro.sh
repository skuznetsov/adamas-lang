#!/usr/bin/env bash
# A checked allocation upcast binds the source result before the first yield.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/nominal_callback_upcast_result_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/nominal-callback.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
sed 's/as(RowValue)/as(OtherRow)/; s/ResultBox(RowValue)/ResultBox(OtherRow)/' "$fixture" > "$work/unrelated.cr"
sed 's/FieldRow.new(number, owner)/FieldRow.new(true, owner)/' "$fixture" > "$work/wrong_argument.cr"
sed 's/FieldRow.new(number, owner)/FieldRow.new(number, RowOwner)/' "$fixture" > "$work/wrong_kind.cr"
awk '
  /^  def initialize\(@number : Int32, @owner : RowOwner\)/ {
    print "  def self.new(number : Int32, owner : RowOwner)\n    RowOwner.new\n  end"
    getline
    next
  }
  { print }
' "$fixture" > "$work/factory.cr"
awk '
  { print }
  /^  def initialize\(@number : Int32, @owner : RowOwner\)/ {
    getline
    print
    print "  def self.new(number : Int32, owner : RowOwner)\n    RowOwner.new\n  end"
  }
' "$fixture" > "$work/factory_override.cr"
sed 's/  def initialize/  private def initialize/' "$fixture" > "$work/private_initializer.cr"
printf 'A\n' > "$work/expected"

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

  for case_name in unrelated wrong_argument wrong_kind factory factory_override private_initializer; do
    status=0
    "${build[@]}" "$work/$case_name.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1 || status=$?
    if [[ "$status" != 1 || -e "$work/invalid" ]]; then
      cat "$work/invalid.log" >&2
      echo "$mode failed to reject $case_name" >&2
      exit 1
    fi
  done
  echo "$mode matched the checked upcast and rejected unrelated casts and arguments"
done
