#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/compiler" >&2
  exit 2
fi

compiler=$1
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
attempts=5

for attempt in $(seq 1 "$attempts"); do
  source_file="$repo_root/tmp_stage2_repo_root_bootstrap_cli_parse_repro_${attempt}.cr"
  log_dir=$(mktemp -d "${TMPDIR:-/tmp}/stage2_repo_root_bootstrap_cli_parse_repro.XXXXXX")
  trap 'rm -f "$source_file"' EXIT

  cat > "$source_file" <<'EOF'
require "./src/compiler/bootstrap_shims"
require "./src/compiler/cli"

1
EOF

  echo "[attempt $attempt/$attempts] $compiler"

  set +e
  env \
    ADAMAS_STOP_AFTER_PARSE=1 \
    ADAMAS_PIPELINE_CACHE=0 \
    ADAMAS_LLVM_CACHE=0 \
    "$repo_root/scripts/timeout_sample_lldb.sh" \
    -t 90 -m 16384 -s 5 -l 10 -n 8 --no-series \
    -o "$log_dir" \
    -- "$compiler" "$source_file" --release -o "$log_dir/out"
  status=$?
  set -e

  rm -f "$source_file"
  trap - EXIT

  case "$status" in
    0)
      ;;
    133|134|138|139)
      echo "reproduced: compiler crashed before STOP_AFTER_PARSE on the repo-root bootstrap_shims+cli parse repro"
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

echo "not reproduced: compiler reached STOP_AFTER_PARSE on all $attempts repo-root bootstrap_shims+cli parse repro attempts"
