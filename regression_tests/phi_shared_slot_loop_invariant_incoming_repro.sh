#!/usr/bin/env bash
# Regression: a phi with >=4 cross-block incoming values shares one alloca
# (phi_slot) across its arms. An incoming defined outside the predecessor
# block it flows from (here: a loop-invariant default defined before the loop,
# in a non-entry block) was shared too; its single def-site store happened
# before the loop, and the other arms' stores clobbered it, so the `else` arm
# yielded the previous iteration's arm value. (S3: the 4-arm `case` in
# interpolation_union_variant_conversions returned a stale variant string.)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phi_shared_slot_loop_invariant_incoming_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/ps.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def pick(base : Int32, flag : Bool) : Int32
  dflt = 0
  if flag
    dflt = base * 7 + 1
  end
  sum = 0
  i = 0
  while i < 4
    v = case i
        when 0 then i * 11 + base
        when 1 then i * 13 + base
        when 2 then i * 17 + base
        else        dflt
        end
    sum += v
    i += 1
  end
  sum
end

# Positive control: every incoming is defined in its own arm (sharing is safe).
def pick_local(base : Int32) : Int32
  sum = 0
  i = 0
  while i < 4
    v = case i
        when 0 then i * 11 + base
        when 1 then i * 13 + base
        when 2 then i * 17 + base
        else        i * 19 + base
        end
    sum += v
    i += 1
  end
  sum
end

# 5 + 18 + 39 + 36 = 98; 5 + 18 + 39 + 62 = 124
code = 0
code |= 1 unless pick(5, true) == 98
code |= 2 unless pick_local(5) == 124
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/ps.cr" --no-prelude -o "$WORK_DIR/ps" >"$WORK_DIR/ps.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/ps.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/ps" 5 512 >"$WORK_DIR/ps.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/ps.run.log"; then
  echo "FAIL: shared phi slot clobbered a loop-invariant incoming" >&2
  cat "$WORK_DIR/ps.run.log" >&2
  exit 1
fi
echo "PASS: phi slot sharing skips incomings defined outside their predecessor"
