#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/compiler" >&2
  exit 2
fi

compiler=$1
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$repo_root/regression_tests/stage2_mir_prepare_timing_repro.cr"
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/stage2_mir_prepare_timing_repro.XXXXXX")

set +e
env ADAMAS_STOP_AFTER_MIR=1 \
  "$repo_root/scripts/timeout_sample_lldb.sh" \
  -t 60 -m 8192 -s 5 -l 10 -n 8 --no-series \
  -o "$log_dir" \
  -- "$compiler" --progress --release --no-prelude --no-link --no-ast-cache \
  "$source_file" -o "$log_dir/out"
status=$?
set -e

if /usr/bin/grep -q "Body 1/1" "$log_dir/command.log"; then
  echo "not reproduced: compiler reached MIR body lowering on the minimal prepare-timing repro"
  exit 0
fi

case "$status" in
  133|134|138|139)
    echo "reproduced: compiler crashed before MIR body lowering on the minimal prepare-timing repro"
    echo "log: $log_dir"
    exit 1
    ;;
  *)
    echo "inconclusive: unexpected status=$status"
    echo "log: $log_dir"
    exit 2
    ;;
esac
