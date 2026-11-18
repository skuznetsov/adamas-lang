#!/usr/bin/env bash
# A recursive result emission belongs to the exact physical consumer body that emitted it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
fixture="$root/regression_tests/recursive_emission_ticket_lifetime_repro.cr"
work="$(mktemp -d "${TMPDIR:-/tmp}/recursive-emission-ticket.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi
sed 's/RecCode.new(66)/66/' "$fixture" > "$work/invalid.cr"
printf 'A\n' > "$work/expected"
graph="$root/regression_tests/fixtures/recursive_callsite_replay.cr"
cp "$graph" "$work/implicit.cr"
sed -e 's/current = read1$/current = self.read1/' -e 's/current = read2$/current = read2()/' \
    -e 's/^\([[:space:]]*\)read2$/\1self.read2/' "$graph" > "$work/explicit.cr"
for syntax in implicit explicit; do
  sed 's/return STOP_2 if @remaining == 0/return Ticket if @remaining == 0/' "$work/$syntax.cr" > "$work/$syntax-invalid.cr"
done
printf 'CD\n' > "$work/expected-graph"

for mode in stock candidate; do
  if [[ "$mode" == stock ]]; then
    build=("$safe" "$stock" 120 4096 build --prelude=empty "${link[@]}")
  else
    build=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  "${build[@]}" "$fixture" -o "$work/$mode" > "$work/$mode.build.log" 2>&1 || {
    cat "$work/$mode.build.log" >&2
    exit 1
  }
  "$safe" "$work/$mode" 8 512 > "$work/$mode.stdout" 2> "$work/$mode.run.log" || {
    cat "$work/$mode.run.log" >&2
    exit 1
  }
  cmp "$work/expected" "$work/$mode.stdout"
  if "${build[@]}" "$work/invalid.cr" -o "$work/$mode.invalid" > "$work/$mode.invalid.log" 2>&1; then
    echo "$mode accepted an invalid RecCode result from parse1" >&2
    exit 1
  fi
  if [[ "$mode" == stock ]]; then
    expected_error='method SmallParser#parse1 must return RecCode but it is returning (Int32 | RecCode)'
  else
    expected_error='method SmallParser#parse1$Bool must return RecCode, but it is returning Int32 | RecCode'
  fi
  grep -Fq "$expected_error" "$work/$mode.invalid.log" || {
    cat "$work/$mode.invalid.log" >&2
    exit 1
  }
  for syntax in implicit explicit; do
    binary="$work/$mode.$syntax"
    "${build[@]}" "$work/$syntax.cr" -o "$binary" > "$binary.build.log" 2>&1 || {
      cat "$binary.build.log" >&2
      exit 1
    }
    "$safe" "$binary" 8 512 > "$binary.stdout" 2> "$binary.run.log" || {
      cat "$binary.run.log" >&2
      exit 1
    }
    cmp "$work/expected-graph" "$binary.stdout"
    if "${build[@]}" "$work/$syntax-invalid.cr" -o "$binary.invalid" > "$binary.invalid.log" 2>&1; then
      echo "$mode accepted a class object as the result of Mini::Parser#read2 ($syntax)" >&2
      exit 1
    fi
    grep -E 'method Mini::Parser#read2 must return Ticket.*Ticket\.class' "$binary.invalid.log" > /dev/null || {
      cat "$binary.invalid.log" >&2
      exit 1
    }
  done
  echo "$mode passed physical recursive result and strict return controls"
done
