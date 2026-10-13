#!/usr/bin/env bash
# Regression: a phi union -> union conversion without descriptor refs remapped
# the discriminator by variant INDEX (0->1, 1->2, 2->3 for
# Bool | Int32 | String -> Nil | Bool | Int32 | String). Stored discriminators
# are global (Nil -> 0, otherwise type_ref.id), so a live Bool (2) became 3 and
# a Nil smuggled through a narrowed slot became Bool. In S2 this turned the
# Nil `trace_phi` local in LLVMIRGenerator#emit_phi truthy, flooding PHI_TRACE
# output until S3 ran out of memory.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_phi_tid_remap_global_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/tr.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

def pick(n : Int32) : Bool | Int32 | String
  if n == 0
    true
  elsif n == 1
    7
  else
    "s"
  end
end

def merge(c : Int32, n : Int32)
  x = if c == 0
        nil
      else
        pick(n)
      end
  x
end

code = 0
v = merge(1, 0)
code |= 1 unless v.is_a?(Bool)
w = merge(0, 0)
code |= 2 unless w.nil?
i = merge(1, 1)
code |= 4 unless i.is_a?(Int32) && i == 7
s = merge(1, 2)
code |= 8 unless s.is_a?(String)
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/tr.cr" --no-prelude -o "$WORK_DIR/tr" >"$WORK_DIR/tr.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/tr.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/tr" 5 512 >"$WORK_DIR/tr.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/tr.run.log"; then
  echo "FAIL: union phi conversion rewrote a global discriminator" >&2
  cat "$WORK_DIR/tr.run.log" >&2
  exit 1
fi
echo "PASS: union phi conversion keeps global discriminators"
