#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/compiler" >&2
  exit 2
fi

compiler=$1
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$repo_root/regression_tests/stage2_parenthesized_block_call_args_repro.cr"
workdir=$(mktemp -d "${TMPDIR:-/tmp}/stage2_parenthesized_block_call_args.XXXXXX")
wrapper="$workdir/run.sh"
log="$workdir/run.log"

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export ADAMAS_STOP_AFTER_PARSE=1
export ADAMAS_TRACE_DEF_STATE=1
exec "$compiler" "$source_file" --no-prelude
EOF
chmod +x "$wrapper"

set +e
"$repo_root/scripts/run_safe.sh" "$wrapper" 10 1024 >"$log" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "reproduced: compiler crashed before proving call-args restoration after a parenthesized trailing block"
  tail -n 80 "$log"
  exit 1
fi

if ! grep -q "\\[DEF_STATE\\] phase=enter line=7 .* call_args=0 " "$log"; then
  if grep -q "\\[DEF_STATE\\] phase=enter line=7 " "$log"; then
    echo "reproduced: compiler reached the next def with leaked call_args state after a parenthesized trailing block"
    grep "\\[DEF_STATE\\] phase=enter line=7 " "$log"
    exit 1
  fi

  echo "inconclusive: next def state was not observed in trace output"
  tail -n 80 "$log"
  exit 2
fi

echo "not reproduced: next def starts with call_args=0 after the parenthesized trailing block repro"
