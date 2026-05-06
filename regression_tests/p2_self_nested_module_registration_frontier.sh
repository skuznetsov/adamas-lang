#!/usr/bin/env bash
# Produced-stage2 guard for qualified module reopen wrappers. A module body may
# contain a nested ModuleNode whose canonical name is the owner itself; that
# wrapper must not recurse back into the same registration frontier.
set -euo pipefail

compiler="${1:-bin/crystal_v2}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d /tmp/cv2_self_nested_module_frontier.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/hello.cr" <<'CR'
puts 42
CR

log="$tmpdir/hello.log"
set +e
"$root_dir/scripts/run_safe.sh" "$compiler" 120 4096 "$tmpdir/hello.cr" -o "$tmpdir/hello_bin" >"$log" 2>&1
status=$?
set -e

if grep -Eq 'Trace/BPT trap|\[EXIT: 133\]' "$log"; then
  echo "p2 self-nested module frontier: compiler hit recursive registration trap" >&2
  tail -120 "$log" >&2
  exit 1
fi

if ! grep -Fq '[STAGE2_DEBUG] module register done' "$log"; then
  echo "p2 self-nested module frontier: compiler did not pass module registration" >&2
  tail -120 "$log" >&2
  exit 1
fi

if (( status != 0 )); then
  if ! grep -Fq '[KILL] Timeout after 120s' "$log"; then
    echo "p2 self-nested module frontier: unexpected compiler exit $status" >&2
    tail -120 "$log" >&2
    exit 1
  fi
fi

echo "p2_self_nested_module_registration_frontier_ok"
