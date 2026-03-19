#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/compiler" >&2
  exit 2
fi

compiler=$1
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$repo_root/regression_tests/stage2_class_super_hir_repro.cr"
attempts=5

for attempt in $(seq 1 "$attempts"); do
  log_dir=$(mktemp -d "${TMPDIR:-/tmp}/stage2_class_super_hir_repro.XXXXXX")
  echo "[attempt $attempt/$attempts] $compiler"

  set +e
  env \
    CRYSTAL_V2_STOP_AFTER_HIR=1 \
    CRYSTAL_V2_PIPELINE_CACHE=0 \
    CRYSTAL_V2_LLVM_CACHE=0 \
    "$repo_root/scripts/timeout_sample_lldb.sh" \
    -t 90 -m 4096 -s 5 -l 10 -n 8 --no-series \
    -o "$log_dir" \
    -- "$compiler" "$source_file" --release --no-prelude -o "$log_dir/out"
  status=$?
  set -e

  case "$status" in
    0)
      ;;
    133|134|138|139)
      echo "reproduced: compiler crashed before STOP_AFTER_HIR on the explicit superclass class repro"
      echo "log: $log_dir"
      exit 1
      ;;
    *)
      echo "inconclusive: unexpected status=$status"
      echo "log: $log_dir"
      exit 2
      ;;
  esac
done

echo "not reproduced: compiler reached STOP_AFTER_HIR on all $attempts explicit superclass class repro attempts"
