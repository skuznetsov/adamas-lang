#!/usr/bin/env bash
# An untyped `**opts` must be specialized per NamedTuple layout, like `*args`
# is per Tuple arity. Collapsing every layout into the shared
# `m$NamedTuple_double_splat` body typed `opts` as a bare NamedTuple, so the
# returned value lost its layout and `z[:a]` read garbage / aborted.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/double_splat_per_layout.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/ds.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def pass_opts(**metadata)
  metadata
end

def pick_b(**metadata)
  metadata[:b]
end

z = pass_opts a: 8, b: 9
w = pass_opts b: 3_i64, c: 2
v = pick_b a: 1, b: 4
u = pick_b b: 5_i64
r = 0
r |= 1 unless z[:a] == 8 && z[:b] == 9
r |= 2 unless w[:b] == 3_i64 && w[:c] == 2
r |= 4 unless v == 4
r |= 8 unless u == 5_i64
LibC.exit(r)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/ds.cr" --no-prelude -o "$WORK_DIR/ds" --emit hir >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  echo "FAIL: compile" >&2
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/ds" 5 512 >"$WORK_DIR/run.log" 2>&1
set -e
if ! grep -q '\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "FAIL: per-layout ** values wrong (bitmask exit):" >&2
  grep '\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo "PASS: untyped ** is specialized per NamedTuple layout"
