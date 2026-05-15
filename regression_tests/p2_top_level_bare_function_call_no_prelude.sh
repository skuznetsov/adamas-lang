#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_top_level_call.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/repro.cr" <<'CR'
def foo
  1
end

foo
CR

log="$tmpdir/repro.log"
out="$tmpdir/repro"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 60 2048 \
  "$tmpdir/repro.cr" --no-prelude -o "$out" \
  >"$log" 2>&1
compile_rc=$?
set -e

if [[ $compile_rc -ne 0 ]]; then
  echo "top-level bare function call guard compile failed" >&2
  tail -n 160 "$log" >&2 || true
  exit 1
fi

if [[ ! -x "$out" ]]; then
  echo "top-level bare function call guard did not produce a binary" >&2
  tail -n 120 "$log" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$out" 5 512 >/dev/null

echo "p2_top_level_bare_function_call_no_prelude_ok"
