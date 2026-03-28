#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <compiler>" >&2
  exit 1
fi

ROOT="/Users/sergey/Projects/Crystal/crystal_v2_repo"
COMPILER="$1"
SRC="$ROOT/regression_tests/stage2_system_write_stdout_smoke.cr"
WORKDIR="$(mktemp -d /tmp/stage2_system_write_stdout.XXXXXX)"
BIN="$WORKDIR/system_write_stdout"
COMPILE_WRAP="$WORKDIR/compile.sh"
RUN_WRAP="$WORKDIR/run.sh"
RUN_LOG="$WORKDIR/run.log"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

cat > "$COMPILE_WRAP" <<EOF
#!/bin/bash
cd "$ROOT" || exit 1
exec "$COMPILER" "$SRC" -o "$BIN"
EOF
chmod +x "$COMPILE_WRAP"
"$ROOT/scripts/run_safe.sh" "$COMPILE_WRAP" 40 2048 >/dev/null

cat > "$RUN_WRAP" <<EOF
#!/bin/bash
exec "$BIN"
EOF
chmod +x "$RUN_WRAP"

if ! "$ROOT/scripts/run_safe.sh" "$RUN_WRAP" 10 512 >"$RUN_LOG" 2>&1; then
  cat "$RUN_LOG" >&2
  echo "reproduced: runtime failed"
  exit 0
fi

if ! rg -q '^\[EXIT: 0\]' "$RUN_LOG"; then
  cat "$RUN_LOG" >&2
  echo "reproduced: missing successful exit"
  exit 0
fi

if ! rg -q '^A$' "$RUN_LOG"; then
  cat "$RUN_LOG" >&2
  echo "reproduced: missing stdout marker"
  exit 0
fi

echo "not reproduced"
