#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <stage1-compiler-bin> [timeout_sec=600] [max_mem_mb=4096]" >&2
  exit 1
fi

STAGE1_BIN="$1"
TIMEOUT="${2:-600}"
MAX_MEM="${3:-4096}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -x "$STAGE1_BIN" ]]; then
  echo "error: stage1 compiler not executable: $STAGE1_BIN" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_nil_slot_bootstrap.XXXXXX")"
WRAPPER="$WORKDIR/run.sh"
LOG="$WORKDIR/run.log"
OUT="$WORKDIR/stage2_debug_nilslot"

cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export CRYSTAL2_STAGE2_DEBUG=1
exec "$STAGE1_BIN" src/adamas.cr -o "$OUT"
EOF
chmod +x "$WRAPPER"

set +e
scripts/run_safe.sh "$WRAPPER" "$TIMEOUT" "$MAX_MEM" > "$LOG" 2>&1
RUN_STATUS=$?
set -e

if ! rg -q '\[STAGE2_TRACE\] step5: generate\(io\) start' "$LOG"; then
  echo "FAIL: stage2 did not reach LLVM generation" >&2
  tail -n 120 "$LOG" >&2
  exit 1
fi

if rg -q 'LLVM_MISSING_VALUE' "$LOG"; then
  echo "FAIL: LLVM_MISSING_VALUE is still present" >&2
  rg -n 'LLVM_MISSING_VALUE' "$LOG" >&2 || true
  tail -n 120 "$LOG" >&2
  exit 1
fi

echo "PASS: no LLVM_MISSING_VALUE during stage2 LLVM generation"
echo "run_safe_status=$RUN_STATUS"
echo "log=$LOG"
rg -n '\[KILL\]|\[EXIT:|\[STAGE2_TRACE\] step5: generate\(io\) start|\[LLVM\] total MIR functions' "$LOG" || true
