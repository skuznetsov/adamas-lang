#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_slice_literal.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

S = Slice(UInt64).literal(1_u64, 2_u64)

LibC.exit(0)
CR

log="$tmpdir/repro.log"
out="$tmpdir/repro"

"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 60 2048 \
  "$tmpdir/repro.cr" --no-prelude --emit llvm-ir --no-link -o "$out" \
  >"$log" 2>&1

if [[ ! -s "$out.ll" ]]; then
  echo "slice literal guard did not emit LLVM IR" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

if grep -Fq 'call void @Slice$LUInt64$R$Dliteral' "$out.ll"; then
  echo "slice literal guard found void Slice(UInt64).literal call" >&2
  grep -n -A4 -B2 -F 'Slice$LUInt64$R$Dliteral' "$out.ll" >&2 || true
  exit 1
fi

if grep -Fq 'store ptr null, ptr @Object__classvar__S' "$out.ll"; then
  echo "slice literal guard found null store for Slice(UInt64).literal constant" >&2
  grep -n -A4 -B4 -F '@Object__classvar__S' "$out.ll" >&2 || true
  exit 1
fi

grep -Eq 'store ptr %r[0-9]+, ptr @Object__classvar__S' "$out.ll"

"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 60 2048 \
  "$tmpdir/repro.cr" --no-prelude -o "$out" \
  >"$log.bin" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$out" 5 512 >"$log.run" 2>&1

echo "p2_slice_literal_no_prelude_ok"
