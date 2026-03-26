#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/compiler" >&2
  exit 2
fi

compiler=$1
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$repo_root/src/stdlib/time.cr"
attempts=5

for attempt in $(seq 1 "$attempts"); do
  workdir=$(mktemp -d "${TMPDIR:-/tmp}/stage2_time_parse_repro.XXXXXX")
  wrapper="$workdir/run.sh"
  log="$workdir/run.log"

  cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export CRYSTAL_V2_STOP_AFTER_PARSE=1
export CRYSTAL_V2_PIPELINE_CACHE=0
export CRYSTAL_V2_LLVM_CACHE=0
exec "$compiler" "$source_file" --release --no-ast-cache -o "$workdir/out"
EOF
  chmod +x "$wrapper"

  set +e
  "$repo_root/scripts/run_safe.sh" "$wrapper" 30 2048 >"$log" 2>&1
  run_status=$?
  set -e

  case "$run_status" in
    0)
      rm -rf "$workdir"
      ;;
    133|134|138|139)
      echo "reproduced: compiler crashed before STOP_AFTER_PARSE on src/stdlib/time.cr"
      echo "attempt: $attempt/$attempts"
      tail -n 80 "$log"
      rm -rf "$workdir"
      exit 1
      ;;
    *)
      echo "inconclusive: unexpected status=$run_status on attempt $attempt/$attempts"
      tail -n 80 "$log"
      rm -rf "$workdir"
      exit 2
      ;;
  esac
done

echo "not reproduced: compiler reached STOP_AFTER_PARSE on src/stdlib/time.cr in all $attempts attempts"
