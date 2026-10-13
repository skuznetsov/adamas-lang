#!/usr/bin/env bash
# Hash(String, Nil)#key_hash with a `Pointer(Void) | String | UInt8` key goes
# through strict union hash dispatch, which needs a real body for every branch.
# When key_hash itself was force-lowered deep in a return-discovery chain, the
# force-lower depth cap left String/UInt8 Object#hash bodiless (Void) and the
# compiler raised "cannot safely lower heterogeneous hash returns".
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_key_hash_depth.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/t.cr" <<'CR'
def pick(i : Int32) : Pointer(Void) | String | UInt8
  case i
  when 0 then Pointer(Void).null
  when 1 then "s"
  else        7_u8
  end
end

h = {"s" => nil} of String => Nil
hit = h.has_key?(pick(ARGV.size + 1))
miss = h.has_key?(pick(ARGV.size + 2))
null_miss = h.has_key?(pick(ARGV.size))
STDERR.puts "#{hit} #{miss} #{null_miss}"
exit(hit && !miss && !null_miss ? 0 : 1)
CR
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1 || { tail -5 "$WORK_DIR/build.log" >&2; exit 1; }
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || { cat "$WORK_DIR/run.log" >&2; exit 1; }
echo union_key_hash_strict_dispatch_depth_repro_ok
