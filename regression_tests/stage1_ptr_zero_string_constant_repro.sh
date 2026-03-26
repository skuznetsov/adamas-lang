#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <stage1_compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage1_ptr_zero_string_constant.XXXXXX")"
SRC="$WORKDIR/ptr_zero_string_repro.cr"
OUT="$WORKDIR/ptr_zero_string_repro_bin"
WRAPPER="$WORKDIR/run_compile.sh"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
puts "ptr 0,"
CR

cat >"$WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$COMPILER" "$SRC" -o "$OUT"
EOF
chmod +x "$WRAPPER"

set +e
compile_output="$("$ROOT_DIR/scripts/run_safe.sh" "$WRAPPER" 60 2048 2>&1)"
status=$?
set -e

if [ $status -ne 0 ] || [ ! -x "$OUT" ]; then
  echo "reproduced: stage1 corrupts LLVM string constants while normalizing ptr 0"
  echo "$compile_output" | tail -n 40
  exit 1
fi

set +e
run_output="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 256 2>&1)"
run_status=$?
set -e

if [ $run_status -ne 0 ] || ! echo "$run_output" | grep -q "ptr 0,"; then
  echo "reproduced: stage1 compiled the repro but runtime output drifted"
  echo "$run_output" | tail -n 20
  exit 1
fi

echo "not reproduced: ptr-zero string literal compiles and runs correctly"
