#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:?usage: $0 <compiler>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="/tmp/stage2_closure_capture_member_mutation_runtime_oracle"
RUNNER="/tmp/stage2_closure_capture_member_mutation_runtime_oracle.run.sh"
LOG="$(mktemp /tmp/stage2_closure_capture_member_mutation_runtime_oracle.XXXXXX.log)"
trap 'rm -f "$OUT" "$RUNNER" "$LOG"' EXIT

cd "$ROOT"
"$COMPILER" regression_tests/stage2_closure_capture_member_mutation_runtime_oracle.cr -o "$OUT"

cat > "$RUNNER" <<EOF_RUNNER
#!/usr/bin/env bash
set -euo pipefail
exec "$OUT" --version
EOF_RUNNER
chmod +x "$RUNNER"

if scripts/run_safe.sh "$RUNNER" 5 512 > "$LOG" 2>&1; then
  if grep -q 'version-false' "$LOG"; then
    echo "not reproduced: captured member mutation no longer corrupts skipped branch readback"
    exit 0
  fi
fi

cat "$LOG"
echo "reproduced: captured member mutation still breaks skipped branch readback"
exit 1
