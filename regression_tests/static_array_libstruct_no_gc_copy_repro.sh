#!/usr/bin/env bash
# Stock-first oracle for the hidden StaticArray(C-struct) IndexGet copy under
# --no-gc. The no-prelude candidate probe avoids unrelated prelude GC
# allocations, so the expected rejection identifies this synthesized copy.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$ROOT_DIR/regression_tests/static_array_libstruct_no_gc_copy.cr"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <stock-crystal-compiler> <candidate-adamas-compiler>" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/static_array_libstruct_no_gc.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "${KEEP_ARTIFACTS:-0}" == "1" || "$status" -ne 0 ]]; then
    echo "artifacts: $WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

stock_binary="$WORK_DIR/stock"
if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$1" 90 8192 \
    build "$FIXTURE" --no-debug -o "$stock_binary" \
    >"$WORK_DIR/stock.compile.stdout" 2>"$WORK_DIR/stock.compile.stderr"; then
  cat "$WORK_DIR/stock.compile.stdout" "$WORK_DIR/stock.compile.stderr" >&2
  echo "stock compile failed" >&2
  exit 1
fi

if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$stock_binary" 5 512 \
    >"$WORK_DIR/stock.run.stdout" 2>"$WORK_DIR/stock.run.stderr"; then
  cat "$WORK_DIR/stock.run.stdout" "$WORK_DIR/stock.run.stderr" >&2
  echo "stock run failed" >&2
  exit 1
fi

if ! printf '0\n' | cmp -s - "$WORK_DIR/stock.run.stdout"; then
  cat "$WORK_DIR/stock.run.stdout" "$WORK_DIR/stock.run.stderr" >&2
  echo "stock output mismatch; expected 0\\n" >&2
  exit 1
fi

candidate_default="$WORK_DIR/candidate-default"
if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$2" 90 8192 \
    build "$FIXTURE" --no-prelude --no-debug -o "$candidate_default" \
    >"$WORK_DIR/candidate-default.compile.stdout" 2>"$WORK_DIR/candidate-default.compile.stderr"; then
  cat "$WORK_DIR/candidate-default.compile.stdout" "$WORK_DIR/candidate-default.compile.stderr" >&2
  echo "candidate no-prelude compile failed without --no-gc" >&2
  exit 1
fi

if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$candidate_default" 5 512 \
    >"$WORK_DIR/candidate-default.run.stdout" 2>"$WORK_DIR/candidate-default.run.stderr"; then
  cat "$WORK_DIR/candidate-default.run.stdout" "$WORK_DIR/candidate-default.run.stderr" >&2
  echo "candidate no-prelude run failed without --no-gc" >&2
  exit 1
fi

if ! printf '0\n' | cmp -s - "$WORK_DIR/candidate-default.run.stdout"; then
  cat "$WORK_DIR/candidate-default.run.stdout" "$WORK_DIR/candidate-default.run.stderr" >&2
  echo "candidate no-prelude output mismatch; expected 0\\n" >&2
  exit 1
fi

# Both MIR scheduling routes must expose the same synthesized GC demand.
for fused in 0 1; do
  candidate_binary="$WORK_DIR/candidate-fused-$fused"
  candidate_stdout="$WORK_DIR/candidate-fused-$fused.compile.stdout"
  candidate_stderr="$WORK_DIR/candidate-fused-$fused.compile.stderr"
  set +e
  ADAMAS_FUSED_PARALLEL="$fused" RUN_SAFE_PASSTHROUGH_STDIO=1 \
    "$SAFE_RUNNER" "$2" 90 8192 \
    build "$FIXTURE" --no-prelude --no-debug --no-gc -o "$candidate_binary" \
    >"$candidate_stdout" 2>"$candidate_stderr"
  candidate_status=$?
  set -e
  if [[ "$candidate_status" -ne 1 ]]; then
    cat "$candidate_stdout" "$candidate_stderr" >&2
    echo "candidate fused=$fused exited $candidate_status; expected diagnostic status 1" >&2
    exit 1
  fi
  if [[ -e "$candidate_binary" ]]; then
    echo "candidate fused=$fused left an executable after a hidden GC copy rejection" >&2
    exit 1
  fi
  if ! rg -Fq 'StaticArray(C struct) index value-copy lowering requires a GC allocation' \
      "$candidate_stderr"; then
    cat "$candidate_stdout" "$candidate_stderr" >&2
    echo "candidate fused=$fused failed without the target StaticArray diagnostic" >&2
    exit 1
  fi
done

echo "static_array_libstruct_no_gc_copy_repro: ok"
