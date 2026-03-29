#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/compiler" >&2
  exit 2
fi

compiler=$1
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workdir=$(mktemp -d "${TMPDIR:-/tmp}/stage1_add_param_shovel_mir_oracle.XXXXXX")
wrapper="$workdir/run.sh"
log="$workdir/run.log"
output_base="$workdir/out"
mir_file="$output_base.mir"
target_func='func @Crystal::HIR::Function#add_param$String_Crystal::HIR::TypeRef('
bad_call='extern_call @Crystal::HIR::Taint#<<$UInt32'
expected_helper='func @Array(UInt32)#<<$UInt32('

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export CRYSTAL_V2_STOP_AFTER_MIR=1
exec "$compiler" "$repo_root/src/crystal_v2.cr" --emit mir -o "$output_base"
EOF
chmod +x "$wrapper"

set +e
"$repo_root/scripts/run_safe.sh" "$wrapper" 420 3072 >"$log" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "reproduced: compiler failed before completing compiler MIR emission"
  tail -n 120 "$log"
  exit 1
fi

if [[ ! -f "$mir_file" ]]; then
  echo "reproduced: compiler exited cleanly but did not write MIR output"
  tail -n 120 "$log"
  exit 1
fi

if ! grep -Fq "$expected_helper" "$mir_file"; then
  echo "reproduced: expected Array(UInt32)#<< specialization missing from compiler MIR"
  exit 1
fi

func_body=$(
  awk -v target="$target_func" '
    index($0, target) { in_func = 1 }
    in_func { print }
    in_func && $0 == "}" { exit }
  ' "$mir_file"
)

if [[ -z "$func_body" ]]; then
  echo "reproduced: add_param function body not found in compiler MIR"
  exit 1
fi

if grep -Fq "$bad_call" <<<"$func_body"; then
  echo "reproduced: add_param first shovel still resolves through stale Taint#<<"
  echo "bad call: $bad_call"
  echo "function excerpt:"
  awk -v target="$target_func" '
    index($0, target) { in_func = 1; count = 0 }
    in_func && count < 40 { print; count++ }
    in_func && count >= 40 { exit }
  ' "$mir_file"
  exit 1
fi

echo "not reproduced: add_param shovel MIR no longer falls back to stale Taint#<<"
