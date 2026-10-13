#!/usr/bin/env bash
# Hash#key_hash intrinsics used to malloc a 24-byte Crystal::Hasher per call
# and never free it (stage2 leaked ~618 MB compiling `puts "hello"`). Where the
# hasher only flows through Hasher#permute (returns self, stores nothing) it
# must live on the stack. Checks: hashing stays correct for Int32/String/
# UInt64/enum/Bytes keys, and the emitted Int32/String/Bytes key_hash bodies do not call
# __adamas_malloc64.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/key_hash_local_hasher.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/t.cr" <<'CR'
enum Col
  Red
  Green
end
hi = {} of Int32 => Int32
hs = {} of String => Int32
hu = {} of UInt64 => Int32
he = {} of Col => Int32
hb = {} of Bytes => Int32
hb["abc".to_slice] = 1
hb["abcdefghijk".to_slice] = 2
i = 0
while i < 2000
  hi[i] = i
  hs["k#{i}"] = i
  hu[i.to_u64 * 7] = i
  i += 1
end
he[Col::Red] = 1
he[Col::Green] = 2
r = 0
r |= 1 unless hi[1234]? == 1234 && hi.size == 2000
r |= 2 unless hs["k777"]? == 777 && hs["nope"]?.nil?
r |= 4 unless hu[7_u64 * 1999]? == 1999
r |= 8 unless he[Col::Green]? == 2
r |= 16 unless 5.hash == 5.hash && "ab".hash == "ab".hash
r |= 32 unless hb["abcdefghijk".to_slice]? == 2 && hb["abc".to_slice]? == 1 && hb["zz".to_slice]?.nil?
exit(r == 0 ? 3 : r + 64)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
mkdir -p "$WORK_DIR/ir"
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/ir/t" --emit llvm-ir >"$WORK_DIR/ir.log" 2>&1; then
  cat "$WORK_DIR/ir.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/run.log"; then
  echo "hash correctness failed (want EXIT 3):" >&2
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
LL="$(ls "$WORK_DIR"/ir/*.ll 2>/dev/null | head -1 || true)"
if [ -z "$LL" ]; then
  echo "no .ll emitted" >&2
  exit 1
fi
checked=0
for suffix in 'key_hash$$Int32' 'key_hash$$String' 'key_hash$$Slice$LUInt8$R'; do
  body="$(awk -v s="$suffix" 'index($0, "define ") == 1 && index($0, s "(") { on = 1 } on { print } on && /^}/ { exit }' "$LL")"
  if [ -z "$body" ]; then echo "no ${suffix} body in $LL" >&2; exit 1; fi
  checked=$((checked + 1))
  if printf '%s\n' "$body" | grep -q '__adamas_malloc64'; then
    echo "key_hash ${suffix} still heap-allocates its Hasher" >&2
    exit 1
  fi
done
if [ "$checked" -ne 3 ]; then
  echo "no key_hash bodies found in $LL" >&2
  exit 1
fi
echo key_hash_local_hasher_stack_repro_ok
