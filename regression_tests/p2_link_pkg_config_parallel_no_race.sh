#!/usr/bin/env bash
# Linker pkg-config invocation must be safe under parallel compilation.
#
# Regression: build_link_flags wrote pkg-config output to a shared
#   "/tmp/crystal_v2_pkg_config_<digest_of_value>.log"
# (and similarly for backtick ldflags). Two parallel `crystal_v2`
# processes hashing the same library name (e.g. "bdw-gc") raced on
# delete/open/read/delete. The losing reader saw an empty log,
# build_link_flags returned no `-L/opt/homebrew/opt/bdw-gc/lib`, and
# the linker reported `ld: library 'gc' not found`.
#
# Fix: include Process.pid in the log path so concurrent processes
# never share the same temp file. This script launches multiple
# concurrent compilations of a tiny program and asserts they all
# produce executable binaries.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
JOBS="${2:-8}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_link_parallel_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/parallel_link.cr"
cat >"$SRC" <<'CR'
puts "parallel_link_ok"
CR

pids=()
for ((i=0; i<JOBS; i++)); do
  out="$TMP_DIR/parallel_link_${i}"
  log="$TMP_DIR/parallel_link_${i}.log"
  "$COMPILER" "$SRC" -o "$out" >"$log" 2>&1 &
  pids+=($!)
done

fail=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    fail=1
  fi
done

missing=0
for ((i=0; i<JOBS; i++)); do
  out="$TMP_DIR/parallel_link_${i}"
  if [[ ! -x "$out" ]]; then
    missing=$((missing + 1))
    echo "missing binary: $out" >&2
    tail -3 "$TMP_DIR/parallel_link_${i}.log" >&2 || true
  fi
done

if (( missing > 0 )); then
  echo "p2 link pkg_config parallel race regression: $missing/$JOBS builds failed" >&2
  exit 1
fi

if (( fail != 0 )); then
  echo "p2 link pkg_config parallel race regression: at least one compile reported nonzero" >&2
  exit 1
fi

echo "p2_link_pkg_config_parallel_no_race_ok"
