#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/compiler" >&2
  exit 2
fi

compiler=$1
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$repo_root/regression_tests/stage2_main_param_mir_oracle.cr"
workdir=$(mktemp -d "${TMPDIR:-/tmp}/stage2_main_param_mir_oracle.XXXXXX")
wrapper="$workdir/run.sh"
log="$workdir/run.log"
output_base="$workdir/out"
mir_file="$output_base.mir"

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export ADAMAS_STOP_AFTER_MIR=1
exec "$compiler" "$source_file" --no-prelude --emit mir -o "$output_base"
EOF
chmod +x "$wrapper"

set +e
"$repo_root/scripts/run_safe.sh" "$wrapper" 10 1024 >"$log" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "reproduced: compiler failed before completing reduced MIR emission"
  tail -n 80 "$log"
  exit 1
fi

if [[ ! -f "$mir_file" ]]; then
  echo "reproduced: compiler exited cleanly but did not write MIR output"
  tail -n 80 "$log"
  exit 1
fi

expected='func @__crystal_main(%0: Int32, %1: Type#54) -> void {'
if ! grep -Fq "$expected" "$mir_file"; then
  echo "reproduced: reduced MIR oracle drifted from the expected __crystal_main(argc, argv) signature"
  echo "expected: $expected"
  echo "actual:"
  sed -n '1,40p' "$mir_file"
  exit 1
fi

echo "not reproduced: reduced MIR oracle preserves __crystal_main(argc, argv) on self-hosted stage2"
