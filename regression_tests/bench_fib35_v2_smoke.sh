#!/usr/bin/env bash
# Targeted smoke: examples/bench_fib35_crystal.cr (CPU-bound, no Fiber yield).
# Usage: bench_fib35_v2_smoke.sh <path-to-crystal_v2-binary>
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:?usage: $0 <crystal_v2-binary>}"
BIN="${TMPDIR:-/tmp}/bench_fib35_v2_smoke.bin"
"$COMPILER" "$ROOT_DIR/examples/bench_fib35_crystal.cr" -o "$BIN"
exec "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 60 512
