#!/usr/bin/env bash
# Zero-argument `hash` on a union that contains a Pointer/Tuple member runs a
# strict check requiring one known return per branch. A member that inherits
# Object#hash (UInt8 here) gets a self-specialized target (UInt8#hash), but a
# nested lower_function_if_needed only queued it, so the branch had no body
# and read as Void: "cannot safely lower heterogeneous hash returns ... UInt8
# -> UInt8#hash: Void" (the stage-3 blocker in Hash(String, Nil)#key_hash).
# Also checks the arity fallback resolves per member (String -> Object#hash),
# not via the caller's resolved name.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_hash_inherited_zero_arg.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/uh.cr" <<'CR'
def pick(i : Int32) : Pointer(Void) | String | UInt8
  case i
  when 0 then Pointer(Void).null
  when 1 then "a"
  else        7_u8
  end
end

r = 0
x = ARGV.size == 0 ? 7_u8 : Pointer(Void).null
r |= 1 unless x.hash == 7_u8.hash
h = {} of String => Nil
h["a"] = nil
r |= 2 unless pick(0).hash == Pointer(Void).null.hash
r |= 4 unless pick(1).hash == "a".hash
r |= 8 unless pick(2).hash == 7_u8.hash
r |= 16 unless h.has_key?(pick(1))
r |= 32 if h.has_key?(pick(2))
STDERR.puts "r=#{r}"
exit(r == 0 ? 3 : 1)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/uh.cr" -o "$WORK_DIR/uh" >"$WORK_DIR/uh.build.log" 2>&1; then
  cat "$WORK_DIR/uh.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/uh" 5 512 >"$WORK_DIR/uh.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/uh.run.log"; then
  echo "uh: want EXIT 3" >&2
  cat "$WORK_DIR/uh.run.log" >&2
  exit 1
fi
echo union_hash_inherited_zero_arg_repro_ok
