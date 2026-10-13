#!/usr/bin/env bash
# Object#hash lowered with self=Object records `hash(Crystal::Hasher)` as a
# virtual target on the broad root Object. Replay collapsed each live child to
# its nearest declaring owner, so Int32 lowered Number#hash(hasher) with the
# abstract self Number -> Crystal::Hasher#number(Number) -> reduce_num(Number),
# an ambiguous MIR call target. Value children must replay under the concrete
# child owner. The union receiver fan-out (`(Nil | Int32)#hash` inside
# Hash#hash) had the same collapse in lower_virtual_target_resolved.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/broad_replay_value_child.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/class_hash.cr" <<'CR'
class A1
end
exit(A1.new.hash == 0 ? 1 : 3)
CR
cat >"$WORK_DIR/union_int_hash.cr" <<'CR'
x = 5.as(Int32 | Int64)
y = 5.as(Int32 | String)
r = 0
r |= 1 unless x.hash == x.hash
r |= 2 unless x.hash == 5.hash
r |= 4 unless y.hash == 5.hash
exit(r == 0 ? 3 : r + 64)
CR
cat >"$WORK_DIR/nilable_value_hash.cr" <<'CR'
h = {} of String => Int32?
h["y"] = nil
h["z"] = 7
exit(h.hash == h.hash ? 3 : 1)
CR
for name in class_hash union_int_hash nilable_value_hash; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT 3):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo broad_replay_value_child_abstract_self_repro_ok
