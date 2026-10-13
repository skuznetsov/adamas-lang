#!/usr/bin/env bash
# Proc#call must wrap a concrete argument into the proc's union parameter
# type. V2 passed the raw scalar where the proc body expected an Int32 | Nil
# union, so is_a?/payload reads saw garbage.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc_call_union_arg_wrap.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun malloc(size : UInt64) : Void*
end

fun __crystal_malloc64(size : UInt64) : Void*
  LibC.malloc(size)
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

r = 0
pr = ->(x : Int32 | Nil) { x.is_a?(Int32) ? x + 1 : 100 }
r |= 1 unless pr.call(11) == 12
r |= 2 unless pr.call(nil) == 100
LibC.exit(r == 0 ? 3 : r)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
    "$WORK_DIR/np.cr" --no-prelude -o "$WORK_DIR/np" >"$WORK_DIR/np.build.log" 2>&1; then
  cat "$WORK_DIR/np.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/np" 5 512 >"$WORK_DIR/np.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/np.run.log"; then
  echo "np: want EXIT 3" >&2
  cat "$WORK_DIR/np.run.log" >&2
  exit 1
fi
echo proc_call_union_arg_wrap_repro_ok
