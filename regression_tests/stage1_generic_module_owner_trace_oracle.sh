#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/compiler" >&2
  exit 2
fi

compiler=$1
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workdir=$(mktemp -d "${TMPDIR:-/tmp}/stage1_generic_module_owner_trace.XXXXXX")
wrapper="$workdir/run.sh"
stderr_log="$workdir/trace.stderr"
stdout_log="$workdir/trace.stdout"

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export DEBUG_TRACE_EACH_WITH_INDEX=1
export DEBUG_CALL_LOOKUP=each_with_index
exec "$compiler" "$repo_root/src/crystal_v2.cr" --release --emit mir >"$stdout_log" 2>"$stderr_log"
EOF
chmod +x "$wrapper"

set +e
"$repo_root/scripts/run_safe.sh" "$wrapper" 45 3072 >/dev/null 2>&1
set -e

if [[ ! -f "$stderr_log" ]]; then
  echo "reproduced: trace log missing"
  exit 1
fi

python3 - "$stderr_log" <<'PY'
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(errors="replace").splitlines()

for idx, line in enumerate(lines):
    if "caller=Enumerable#index$block" not in line:
        continue

    window = lines[idx:idx + 12]
    saw_bare_recv = any(
        "block_param_types_for_call enter base=Enumerable#each_with_index" in entry and
        "recv=Enumerable func_def=true" in entry
        for entry in window
    )
    saw_void_infer = any(
        "infer_yield_param_types func=Enumerable#each_with_index" in entry and
        "recv=Enumerable" in entry
        for entry in window
    ) and any(
        "inferred_from_body=Void,Int32" in entry
        for entry in window
    )

    if saw_bare_recv or saw_void_infer:
        print("reproduced: generic module owner degraded to bare Enumerable during each_with_index lowering")
        for entry in window:
            if "[CALL_LOWER" in entry or "[CALL_LOOKUP" in entry or "[TRACE_EWI]" in entry:
                print(entry)
        sys.exit(1)

print("not reproduced: Enumerable#index no longer lowers each_with_index with bare module owner")
PY
