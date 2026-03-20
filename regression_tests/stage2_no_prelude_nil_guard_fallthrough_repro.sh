#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

compiler="$1"
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workdir="$(mktemp -d "${TMPDIR:-/tmp}/stage2_no_prelude_nil_guard.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

src="$workdir/repro.cr"
out_bin="$workdir/repro_bin"
compile_stdout="$workdir/compile_stdout.txt"
compile_stderr="$workdir/compile_stderr.txt"
run_log="$workdir/run.log"

cat >"$src" <<'CR'
@[Acyclic]
class TreeNode
  @value : Int32

  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end
end

lib LibC
  fun abort : NoReturn
end

def foo(node : TreeNode?) : Int32
  if node.nil?
    return 0
  end

  node.value
end

LibC.abort if foo(TreeNode.new(7)) != 7
CR

set +e
"$compiler" "$src" --no-prelude -o "$out_bin" >"$compile_stdout" 2>"$compile_stderr"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "inconclusive: compile failed with status=$compile_status" >&2
  echo "--- compiler stdout ---" >&2
  cat "$compile_stdout" >&2
  echo "--- compiler stderr ---" >&2
  cat "$compile_stderr" >&2
  exit 2
fi

set +e
"$repo_root/scripts/run_safe.sh" "$out_bin" 5 512 >"$run_log" 2>&1
run_status=$?
set -e

if [[ $run_status -eq 0 ]]; then
  echo "not reproduced"
  exit 0
fi

if rg -q '\[CRASH\] Segfault|\[CRASH\] Abort' "$run_log"; then
  echo "reproduced: no-prelude nil-guard fallthrough still crashes at runtime"
  exit 1
fi

echo "inconclusive: runtime failed with status=$run_status" >&2
echo "--- run log ---" >&2
cat "$run_log" >&2
exit 2
