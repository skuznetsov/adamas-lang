#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/run_safe_lsof_probe.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/lsof" <<'SH'
#!/bin/sh
sleep 10
SH
chmod +x "$TMP_DIR/lsof"

LOG="$TMP_DIR/run_safe.log"
set +e
PATH="$TMP_DIR:$PATH" "$ROOT_DIR/scripts/run_safe.sh" /bin/sleep 1 64 5 >"$LOG" 2>&1
RC=$?
set -e

if [[ "$RC" -ne 1 ]]; then
  echo "expected run_safe timeout exit 1, got $RC" >&2
  cat "$LOG" >&2
  exit 1
fi

if ! grep -q "\[KILL\] Timeout after 1s" "$LOG"; then
  echo "expected timeout marker in run_safe output" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "run_safe_lsof_timeout_probe_ok"
