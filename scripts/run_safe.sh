#!/bin/bash
# Safe runner for Crystal V2 test binaries
# Prevents FD leaks and memory exhaustion from freezing the machine
# Usage: scripts/run_safe.sh <binary> [timeout_sec] [max_mem_mb] [args...]
# Set RUN_SAFE_PASSTHROUGH_STDIO=1 for stdio protocol servers. In that mode the
# child keeps stdin/stdout, while run_safe diagnostics go to stderr.
BINARY="$1"
TIMEOUT="${2:-5}"
MAX_MEM="${3:-512}"
shift $(( $# >= 3 ? 3 : $# ))

if [ -z "$BINARY" ]; then
  echo "Usage: $0 <binary> [timeout_sec=5] [max_mem_mb=512] [args...]"
  exit 1
fi

STDOUT_TMP=$(mktemp /tmp/run_safe_stdout.XXXXXX)
STDERR_TMP=$(mktemp /tmp/run_safe_stderr.XXXXXX)
WATCHDOG_PID=""
PASSTHROUGH_STDIO="${RUN_SAFE_PASSTHROUGH_STDIO:-0}"

log_line() {
  if [ "$PASSTHROUGH_STDIO" = "1" ]; then
    echo "$@" >&2
  else
    echo "$@"
  fi
}

dump_captured_output() {
  if [ "$PASSTHROUGH_STDIO" = "1" ]; then
    if [ -s "$STDERR_TMP" ]; then
      log_line "=== STDERR ==="
      cat "$STDERR_TMP" >&2
    fi
  else
    echo "=== STDOUT ==="
    cat "$STDOUT_TMP"
    echo "=== STDERR ==="
    cat "$STDERR_TMP"
  fi
}

cleanup() {
  if [ -n "$WATCHDOG_PID" ]; then
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
  fi
  rm -f "$STDOUT_TMP" "$STDERR_TMP"
}
trap cleanup EXIT
trap 'exit 1' TERM

fd_count_for_pid() {
  local target_pid="$1"
  local tmp
  tmp=$(mktemp /tmp/run_safe_lsof.XXXXXX) || return 0

  # lsof can block on a wedged compiler process. Bound the probe so the
  # safety wrapper's wall-clock timeout remains authoritative.
  (lsof -n -P -p "$target_pid" 2>/dev/null | wc -l | tr -d ' ' >"$tmp") &
  local lsof_pid=$!
  local ticks=0
  while [ $ticks -lt 10 ]; do
    if ! kill -0 "$lsof_pid" 2>/dev/null; then
      wait "$lsof_pid" 2>/dev/null || true
      cat "$tmp"
      rm -f "$tmp"
      return 0
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done

  kill -9 "$lsof_pid" 2>/dev/null || true
  wait "$lsof_pid" 2>/dev/null || true
  rm -f "$tmp"
  echo ""
}

kill_child_briefly() {
  local target_pid="$1"
  kill -9 "$target_pid" 2>/dev/null || true

  local ticks=0
  while [ $ticks -lt 20 ]; do
    if ! kill -0 "$target_pid" 2>/dev/null; then
      wait "$target_pid" 2>/dev/null || true
      return 0
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done

  # If the child is stuck in an uninterruptible kernel state, do not let
  # run_safe hang behind it. The orphan is visible to ps and can be cleaned up
  # later, while this wrapper returns a failing timeout signal immediately.
  return 0
}

if [ "$PASSTHROUGH_STDIO" = "1" ]; then
  "$BINARY" "$@" <&0 >&1 2> "$STDERR_TMP" &
else
  "$BINARY" "$@" > "$STDOUT_TMP" 2> "$STDERR_TMP" &
fi
PID=$!
RUN_SAFE_PID=$$

(
  # Fire slightly after the normal monitor timeout. This watchdog is only a
  # backstop for blocked probes/waits, not the primary timeout path.
  sleep $((TIMEOUT + 2))
  if kill -0 "$PID" 2>/dev/null; then
    FD_COUNT=$(fd_count_for_pid "$PID")
    RSS=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ')
    log_line "[KILL] Timeout after ${TIMEOUT}s (FDs: ${FD_COUNT:-?}, RSS: ${RSS:-?}KB)"
    kill_child_briefly "$PID"
    dump_captured_output
    kill -TERM "$RUN_SAFE_PID" 2>/dev/null || true
  fi
) &
WATCHDOG_PID=$!

# Monitor loop (0.5s granularity)
HALF_SECS=0
MAX_HALF_SECS=$((TIMEOUT * 2))
while [ $HALF_SECS -lt $MAX_HALF_SECS ]; do
  if ! kill -0 $PID 2>/dev/null; then
    wait $PID
    EXIT=$?
    dump_captured_output
    if [ $EXIT -eq 139 ]; then log_line "[CRASH] Segfault (exit 139)"; fi
    if [ $EXIT -eq 134 ]; then log_line "[CRASH] Abort (exit 134)"; fi
    SECS=$((HALF_SECS / 2))
    log_line "[EXIT: $EXIT] after ~${SECS}s"
    exit $EXIT
  fi

  # Check FD count (macOS lsof)
  FD_COUNT=$(fd_count_for_pid "$PID")
  # Check RSS in KB
  RSS=$(ps -o rss= -p $PID 2>/dev/null | tr -d ' ')

  if [ -n "$FD_COUNT" ] && [ "$FD_COUNT" -gt 1000 ]; then
    SECS=$((HALF_SECS / 2))
    log_line "[KILL] FD leak detected: $FD_COUNT FDs after ~${SECS}s"
    kill_child_briefly "$PID"
    dump_captured_output
    exit 1
  fi

  if [ -n "$RSS" ] && [ "$RSS" -gt $((MAX_MEM * 1024)) ]; then
    SECS=$((HALF_SECS / 2))
    log_line "[KILL] Memory limit: ${RSS}KB > ${MAX_MEM}MB after ~${SECS}s"
    kill_child_briefly "$PID"
    dump_captured_output
    exit 1
  fi

  sleep 0.5
  HALF_SECS=$((HALF_SECS + 1))
done

# Timeout
FD_COUNT=$(fd_count_for_pid "$PID")
RSS=$(ps -o rss= -p $PID 2>/dev/null | tr -d ' ')
log_line "[KILL] Timeout after ${TIMEOUT}s (FDs: ${FD_COUNT:-?}, RSS: ${RSS:-?}KB)"
kill_child_briefly "$PID"
dump_captured_output
exit 1
