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
sed 's/return STOP_2 if @remaining == 0/return Ticket if @remaining == 0/' "$graph" > "$work/invalid-graph.cr"
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
  "${build[@]}" "$graph" -o "$work/$mode.graph" > "$work/$mode.graph.build.log" 2>&1 || {
    cat "$work/$mode.graph.build.log" >&2
    exit 1
  }
  "$safe" "$work/$mode.graph" 8 512 > "$work/$mode.graph.stdout" 2> "$work/$mode.graph.run.log" || {
    cat "$work/$mode.graph.run.log" >&2
    exit 1
  }
  cmp "$work/expected-graph" "$work/$mode.graph.stdout"
  if "${build[@]}" "$work/invalid-graph.cr" -o "$work/$mode.invalid-graph" > "$work/$mode.invalid-graph.log" 2>&1; then
    echo "$mode accepted a class object as the result of Mini::Parser#read2" >&2
    exit 1
  fi
  grep -E 'method Mini::Parser#read2 must return Ticket.*Ticket\.class' "$work/$mode.invalid-graph.log" > /dev/null || {
    cat "$work/$mode.invalid-graph.log" >&2
    exit 1
  }
  echo "$mode passed physical recursive result and strict return controls"
done
