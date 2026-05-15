#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_nilable_union_wrap.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/repro.cr" <<'CR'
x : UInt32? = nil
if x
  1
else
  0
end
CR

log="$tmpdir/repro.log"
out="$tmpdir/repro"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 60 2048 \
  --no-prelude "$tmpdir/repro.cr" -o "$out" \
  >"$log" 2>&1
compile_rc=$?
set -e

if [[ $compile_rc -ne 0 ]]; then
  echo "nilable union wrap codegen guard compile failed" >&2
  tail -n 160 "$log" >&2 || true
  exit 1
fi

if [[ ! -x "$out" ]]; then
  echo "nilable union wrap codegen guard did not produce a binary" >&2
  tail -n 120 "$log" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$out" 5 512 >/dev/null

echo "p2_nilable_union_wrap_codegen_no_prelude_ok"
