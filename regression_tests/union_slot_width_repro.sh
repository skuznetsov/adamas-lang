#!/usr/bin/env bash
# Falsifier for union-to-union reinterpret slots sized to the source layout.
#
# The backend converts between two union layouts by storing the source union
# into a stack slot and loading the destination union type back out of it. When
# the slot was allocated with the source layout and the destination layout is
# wider, the load reads past the end of the slot: a stack out-of-bounds read
# that returns adjacent frame bytes as union payload. ASan recorded this as a
# READ16 from a 12-byte slot in infer_type_from_expr_inner (Nil|Bool stored,
# Nil|Bool|String loaded).
#
# The probe compiles a Dir.glob program to LLVM IR and scans the IR for any
# alloca/load pair whose loaded union type is wider than the allocated one.
#
# usage: regression_tests/union_slot_width_repro.sh [path-to-compiler]
set -euo pipefail

compiler=${1:-bin/adamas}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compiler=$(cd "$(dirname "$compiler")" && pwd)/$(basename "$compiler")

workdir=$(mktemp -d "${TMPDIR:-/tmp}/union_slot_width_repro.XXXXXX")
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

ir="$workdir/probe.ll"
emit_wrap="$workdir/emit.sh"

cat >"$emit_wrap" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export ADAMAS_LLVM_WORKERS=1
export ADAMAS_LLVM_REUSE_BLOCK_BUFFER=1
exec "$compiler" "$repo_root/regression_tests/stage2_dir_glob_dir_probe.cr" --emit llvm-ir >"$ir"
EOF
chmod +x "$emit_wrap"

"$repo_root/scripts/run_safe.sh" "$emit_wrap" 420 3072 >"$workdir/emit.log" 2>&1 || {
  cat "$workdir/emit.log" >&2
  echo "inconclusive: probe failed to emit LLVM IR"
  exit 2
}

if [[ ! -s "$ir" ]]; then
  echo "inconclusive: probe emitted no LLVM IR"
  exit 2
fi

if "$repo_root/regression_tests/union_slot_oob_scan.py" "$ir"; then
  echo "not reproduced: every union reinterpret slot covers the loaded layout"
  exit 0
fi

echo "reproduced: union reinterpret slot read past its allocation"
exit 1
