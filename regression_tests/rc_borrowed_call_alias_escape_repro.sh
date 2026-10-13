#!/usr/bin/env bash
# A reference returned by a call without proven +1 ownership is borrowed and
# may alias its receiver (`def me : self; self; end`). V2's per-block ARC
# rc_dec'd the owned receiver temp at block end while the borrowed alias was
# still live in a later block or returned, freeing the object under it.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rc_borrowed_alias.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
HDR='lib LibC
  fun exit(code : Int32) : NoReturn
  fun malloc(size : UInt64) : Void*
  fun memset(p : Void*, c : Int32, n : UInt64) : Void*
end

class C
  def initialize; @sum = 15; end
  def sum; @sum; end
  def me : self
    self
  end
end

def churn
  # Reuse freed chunks so a dangling pointer reads garbage.
  i = 0
  while i < 64
    p = LibC.malloc(24_u64)
    LibC.memset(p, 0x5a, 24_u64)
    i += 1
  end
end
'
# Owned temp receiver, borrowed alias returned from the def.
{ echo "$HDR"; cat <<'CR'; } >"$WORK_DIR/ret.cr"
def mk : C
  C.new.me
end
r = mk
churn
LibC.exit(r.sum == 15 ? 3 : 1)
CR
# Owned local, borrowed alias used across blocks after the owner's last use.
{ echo "$HDR"; cat <<'CR'; } >"$WORK_DIR/xblk.cr"
c = C.new
r = c.me
code = 0
code |= 1 if c.sum != 15
churn
code |= 2 if r.sum != 15
LibC.exit(code == 0 ? 3 : code + 10)
CR
for name in ret xblk; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 4096 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/$name.run.log"; then
    echo "$name: want EXIT 3" >&2
    cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo PASS
