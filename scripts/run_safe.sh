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

case "$TIMEOUT" in
  ''|*[!0-9]*|0) echo "error: timeout_sec must be a positive integer" >&2; exit 2 ;;
esac
case "$MAX_MEM" in
  ''|*[!0-9]*|0) echo "error: max_mem_mb must be a positive integer" >&2; exit 2 ;;
esac

STDOUT_TMP=$(mktemp /tmp/run_safe_stdout.XXXXXX)
STDERR_TMP=$(mktemp /tmp/run_safe_stderr.XXXXXX)
STATE_DIR=$(mktemp -d /tmp/run_safe_state.XXXXXX)
WATCHDOG_PID=""
PID=""
TARGET_PGID=""
PASSTHROUGH_STDIO="${RUN_SAFE_PASSTHROUGH_STDIO:-0}"
RUN_SAFE_SUPERVISOR_PID=$$
export RUN_SAFE_SUPERVISOR_PID

# Resource evidence is sampled from the supervised process tree. A missing or
# unusable probe remains explicitly unknown; an empty string must never be
# interpreted as zero by a cap check or by the final machine-readable line.
RSS_AVAILABLE="unknown"
FD_AVAILABLE="unknown"
TREE_MODE="unknown"
PS_TREE_AVAILABLE="unknown"
TREE_COMPLETE_SAMPLES=0
TREE_INCOMPLETE_SAMPLES=0
TREE_MODE_USED="unknown"
RSS_SAMPLES=0
FD_SAMPLES=0
TREE_SAMPLES=0
MAX_TREE_PIDS=0
MAX_RSS_KB=""
MAX_FD=""
CURRENT_RSS_KB=""
CURRENT_FD_COUNT=""
FINISHING=0
FINISHED_MARKER="$STATE_DIR/finished"
WATCHDOG_MARKER="$STATE_DIR/watchdog"
WATCHDOG_REASON_FILE="$STATE_DIR/watchdog.reason"
WATCHDOG_SLEEP_FILE="$STATE_DIR/watchdog.sleep"

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

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

bounded_capture() {
  local tmp
  local probe_pid
  local ticks=0
  local rc
  tmp=$(mktemp /tmp/run_safe_probe.XXXXXX) || return 125
  "$@" >"$tmp" 2>/dev/null &
  probe_pid=$!
  while kill -0 "$probe_pid" 2>/dev/null; do
    if [ "$ticks" -ge 20 ]; then
      kill -9 "$probe_pid" 2>/dev/null || true
      wait "$probe_pid" 2>/dev/null || true
      rm -f "$tmp"
      CAPTURE_OUTPUT=""
      return 124
    fi
    sleep 0.05
    ticks=$((ticks + 1))
  done
  wait "$probe_pid"
  rc=$?
  CAPTURE_OUTPUT=$(cat "$tmp" 2>/dev/null || true)
  rm -f "$tmp"
  return "$rc"
}

detect_resource_tools() {
  local probe
  if command -v ps >/dev/null 2>&1; then
    if bounded_capture ps -o pid= -p "$$"; then
      probe=$(printf '%s' "$CAPTURE_OUTPUT" | tr -d '[:space:]')
      if is_uint "$probe" && [ "$probe" = "$$" ]; then
        RSS_AVAILABLE="yes"
      fi
    fi
    if bounded_capture ps -axo pid=,ppid=; then
      if printf '%s\n' "$CAPTURE_OUTPUT" | awk -v root="$$" '$1 == root && $2 ~ /^[0-9]+$/ { found=1 } END { exit !found }'; then
        PS_TREE_AVAILABLE="yes"
      fi
    fi
  fi
  if command -v lsof >/dev/null 2>&1 && probe_lsof; then
    FD_AVAILABLE="yes"
  fi

  if command -v pgrep >/dev/null 2>&1; then
    TREE_MODE="pgrep"
  elif [ "$PS_TREE_AVAILABLE" = "yes" ]; then
    # collect_tree_pids has a ps -axo fallback for hosts without pgrep.
    TREE_MODE="ps"
  fi
}

probe_lsof() {
  local count
  bounded_capture lsof -n -P -F f -p "$$" || return 1
  count=$(count_lsof_fds "$CAPTURE_OUTPUT")
  is_uint "$count" && [ "$count" -gt 0 ]
}

count_lsof_fds() {
  printf '%s\n' "$1" | awk '
    /^f([0-9]+[[:alpha:]]?|cwd|err|jld|ltx|M[0-9]+|m86|mem|mmap|pd|rtd|tr|txt|v86)$/ { count += 1 }
    END { print count + 0 }
  '
}

contains_pid() {
  local wanted="$1"
  local existing
  for existing in $TREE_PIDS; do
    [ "$existing" = "$wanted" ] && return 0
  done
  return 1
}

append_ps_tree() {
  local ps_table
  local ps_tree
  local child_pid
  bounded_capture ps -axo pid=,ppid= || return 1
  ps_table="$CAPTURE_OUTPUT"
  if [ -n "$ps_table" ]; then
    ps_tree=$(printf '%s\n' "$ps_table" | awk -v root="$PID" '
      { pid[NR] = $1; parent[$1] = $2; count = NR }
      END {
        found[root] = 1
        changed = 1
        while (changed) {
          changed = 0
          for (i = 1; i <= count; i++) {
            if (!found[pid[i]] && found[parent[pid[i]]]) {
              found[pid[i]] = 1
              changed = 1
            }
          }
        }
        for (i = 1; i <= count; i++) if (found[pid[i]]) print pid[i]
      }
    ')
    for child_pid in $ps_tree; do
      if is_uint "$child_pid" && ! contains_pid "$child_pid"; then
        TREE_PIDS="$TREE_PIDS $child_pid"
        TREE_PID_COUNT=$((TREE_PID_COUNT + 1))
      fi
    done
    printf '%s\n' "$ps_tree" | awk -v root="$PID" '$1 == root { found=1 } END { exit !found }' || return 1
    TREE_SAMPLE_COMPLETE=1
    TREE_SAMPLE_MODE="ps"
    return 0
  fi
  return 1
}

collect_tree_pids() {
  TREE_PIDS="$PID"
  TREE_PID_COUNT=0
  TREE_SAMPLE_COMPLETE=0
  TREE_SAMPLE_MODE="unknown"
  if ! is_uint "$PID"; then
    return 0
  fi
  TREE_PID_COUNT=1

  if [ "$TREE_MODE" = "pgrep" ]; then
    local queue="$PID"
    local parent_pid
    local child_pid
    local pgrep_rc
    local pgrep_output
    local pgrep_ok=1
    while [ -n "$queue" ]; do
      parent_pid="${queue%% *}"
      if [ "$queue" = "$parent_pid" ]; then
        queue=""
      else
        queue="${queue#* }"
      fi
      bounded_capture pgrep -P "$parent_pid"
      pgrep_rc=$?
      pgrep_output="$CAPTURE_OUTPUT"
      if [ "$pgrep_rc" -eq 1 ] && [ -z "$pgrep_output" ]; then
        continue
      fi
      if [ "$pgrep_rc" -ne 0 ] || [ -z "$pgrep_output" ]; then
        pgrep_ok=0
        break
      fi
      for child_pid in $pgrep_output; do
        if ! is_uint "$child_pid"; then
          pgrep_ok=0
          break
        fi
        if is_uint "$child_pid" && ! contains_pid "$child_pid"; then
          TREE_PIDS="$TREE_PIDS $child_pid"
          TREE_PID_COUNT=$((TREE_PID_COUNT + 1))
          queue="$queue $child_pid"
        fi
      done
      [ "$pgrep_ok" = "1" ] || break
    done
    if [ "$pgrep_ok" = "1" ]; then
      TREE_SAMPLE_COMPLETE=1
      TREE_SAMPLE_MODE="pgrep"
      return 0
    fi
    if [ "$PS_TREE_AVAILABLE" = "yes" ]; then
      TREE_PIDS="$PID"
      TREE_PID_COUNT=1
      append_ps_tree && return 0
    fi
    return 0
  fi

  if [ "$TREE_MODE" = "ps" ]; then
    append_ps_tree
  fi
}

fd_count_for_pids() {
  local pid_csv="$1"
  local count
  bounded_capture lsof -n -P -F f -p "$pid_csv" || return 1
  count=$(count_lsof_fds "$CAPTURE_OUTPUT")
  if is_uint "$count" && [ "$count" -gt 0 ]; then
    printf '%s\n' "$count"
    return 0
  fi
  return 1
}

sample_resources() {
  if ! is_uint "$PID"; then
    return 0
  fi

  CURRENT_RSS_KB=""
  CURRENT_FD_COUNT=""
  collect_tree_pids
  TREE_SAMPLES=$((TREE_SAMPLES + 1))
  if [ "$TREE_SAMPLE_COMPLETE" = "1" ]; then
    TREE_COMPLETE_SAMPLES=$((TREE_COMPLETE_SAMPLES + 1))
    if [ "$TREE_MODE_USED" = "unknown" ]; then
      TREE_MODE_USED="$TREE_SAMPLE_MODE"
    elif [ "$TREE_MODE_USED" != "$TREE_SAMPLE_MODE" ]; then
      TREE_MODE_USED="mixed"
    fi
  else
    TREE_INCOMPLETE_SAMPLES=$((TREE_INCOMPLETE_SAMPLES + 1))
  fi
  if [ "$TREE_PID_COUNT" -gt "$MAX_TREE_PIDS" ]; then
    MAX_TREE_PIDS="$TREE_PID_COUNT"
  fi

  if [ "$RSS_AVAILABLE" = "yes" ]; then
    local rss_total=0
    local rss_seen=0
    local target_pid
    local rss
    for target_pid in $TREE_PIDS; do
      if bounded_capture ps -o rss= -p "$target_pid"; then
        rss=$(printf '%s' "$CAPTURE_OUTPUT" | tr -d '[:space:]')
      else
        rss=""
      fi
      if is_uint "$rss"; then
        rss_total=$((rss_total + rss))
        rss_seen=$((rss_seen + 1))
      fi
    done
    if [ "$TREE_SAMPLE_COMPLETE" = "1" ] && [ "$rss_seen" -eq "$TREE_PID_COUNT" ]; then
      CURRENT_RSS_KB="$rss_total"
      RSS_SAMPLES=$((RSS_SAMPLES + 1))
      if [ -z "$MAX_RSS_KB" ] || [ "$rss_total" -gt "$MAX_RSS_KB" ]; then
        MAX_RSS_KB="$rss_total"
      fi
    fi
  fi

  if [ "$FD_AVAILABLE" = "yes" ]; then
    local pid_csv=""
    local target_pid
    for target_pid in $TREE_PIDS; do
      if [ -z "$pid_csv" ]; then pid_csv="$target_pid"; else pid_csv="$pid_csv,$target_pid"; fi
    done
    local fd_count
    fd_count=$(fd_count_for_pids "$pid_csv" 2>/dev/null || true)
    # A zero-row lsof result means the target disappeared or lsof was denied;
    # never publish it as an observed zero-FD sample.
    if [ "$TREE_SAMPLE_COMPLETE" = "1" ] && is_uint "$fd_count" && [ "$fd_count" -gt 0 ]; then
      CURRENT_FD_COUNT="$fd_count"
      FD_SAMPLES=$((FD_SAMPLES + 1))
      if [ -z "$MAX_FD" ] || [ "$fd_count" -gt "$MAX_FD" ]; then
        MAX_FD="$fd_count"
      fi
    fi
  fi
}

kill_child_briefly() {
  local target_pid="$1"
  local kill_target="$target_pid"
  if [ -n "$TARGET_PGID" ] && [ "$TARGET_PGID" = "$target_pid" ]; then
    kill_target="-$TARGET_PGID"
  fi

  # Give a nested run_safe wrapper a brief TERM window so its own EXIT trap can
  # clean the separately-grouped target it supervises. Sandboxed macOS runners
  # can deny pgrep, so the outer wrapper cannot rely on walking that inner tree.
  if kill -0 "$target_pid" 2>/dev/null; then
    kill -TERM "$target_pid" 2>/dev/null || true
    local term_ticks=0
    local term_limit=5
    case "$BINARY" in
      */run_safe.sh|run_safe.sh) term_limit=30 ;;
    esac
    while [ $term_ticks -lt $term_limit ]; do
      if ! kill -0 "$target_pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
      term_ticks=$((term_ticks + 1))
    done
  fi
  # Walk any survivors only after the graceful window. Killing an inner
  # supervisor's target first would make its own cleanup lose ancestry.
  kill_descendants "$target_pid"
  kill -9 -- "$kill_target" 2>/dev/null || true

  local ticks=0
  while [ $ticks -lt 20 ]; do
    if ! kill -0 -- "$kill_target" 2>/dev/null; then
      wait "$target_pid" 2>/dev/null || true
      PID=""
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

kill_descendants() {
  local parent_pid="$1"
  local child_pid
  local children=""
  if command -v pgrep >/dev/null 2>&1 && bounded_capture pgrep -P "$parent_pid"; then
    children="$CAPTURE_OUTPUT"
  fi
  for child_pid in $children; do
    is_uint "$child_pid" || continue
    kill_descendants "$child_pid"
    kill -9 "$child_pid" 2>/dev/null || true
  done
}

stop_watchdog() {
  local watchdog_pid="$1"
  local sleep_pid=""
  local ticks=0
  [ -n "$watchdog_pid" ] || return 0
  kill -TERM "$watchdog_pid" 2>/dev/null || true
  # Prefer the explicit sleep PID; pgrep may be denied in sandboxed runners.
  while [ $ticks -lt 10 ]; do
    sleep_pid=$(sed -n '1p' "$WATCHDOG_SLEEP_FILE" 2>/dev/null || true)
    if is_uint "$sleep_pid"; then
      kill -TERM "$sleep_pid" 2>/dev/null || true
      kill -9 "$sleep_pid" 2>/dev/null || true
      break
    fi
    sleep 0.01
    ticks=$((ticks + 1))
  done
  # The watchdog owns a sleep child. Reap the child tree before killing the
  # shell so it cannot outlive cleanup as a hidden orphan.
  kill_descendants "$watchdog_pid"
  kill -9 "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
}

emit_resource_line() {
  local outcome="$1"
  local exit_code="$2"
  local reason="$3"
  local max_rss="${MAX_RSS_KB:-unknown}"
  local max_fd="${MAX_FD:-unknown}"
  local rss_available="$RSS_AVAILABLE"
  local fd_available="$FD_AVAILABLE"
  local process_tree_mode="$TREE_MODE_USED"
  local tree_coverage="complete"
  if [ "$TREE_INCOMPLETE_SAMPLES" -gt 0 ] || [ "$TREE_COMPLETE_SAMPLES" -eq 0 ]; then
    tree_coverage="unknown"
    max_rss="unknown"
    max_fd="unknown"
    rss_available="unknown"
    fd_available="unknown"
    process_tree_mode="unknown"
  fi
  [ "$RSS_SAMPLES" -gt 0 ] || rss_available="unknown"
  [ "$FD_SAMPLES" -gt 0 ] || fd_available="unknown"

  # Keep this one-line, key=value format stable for bootstrap/report parsers.
  # RSS is summed across the observed process tree and is measured in KB;
  # max_fd is the aggregate lsof row count for that same tree.
  log_line "[RESOURCE] outcome=$outcome reason=$reason exit_code=$exit_code max_rss_kb=$max_rss max_fd=$max_fd rss_samples=$RSS_SAMPLES fd_samples=$FD_SAMPLES rss_available=$rss_available fd_available=$fd_available process_tree_mode=$process_tree_mode tree_coverage=$tree_coverage tree_samples=$TREE_SAMPLES tree_complete_samples=$TREE_COMPLETE_SAMPLES tree_incomplete_samples=$TREE_INCOMPLETE_SAMPLES max_tree_pids=$MAX_TREE_PIDS"
}

cleanup() {
  if [ -n "$WATCHDOG_PID" ]; then
    stop_watchdog "$WATCHDOG_PID"
    WATCHDOG_PID=""
  fi
  if [ -n "$PID" ]; then
    kill_child_briefly "$PID"
  fi
  rm -f "$STDOUT_TMP" "$STDERR_TMP" "$WATCHDOG_REASON_FILE" "$WATCHDOG_SLEEP_FILE"
  rmdir "$FINISHED_MARKER" "$WATCHDOG_MARKER" 2>/dev/null || true
  rm -rf "$STATE_DIR"
}

finish() {
  local exit_code="$1"
  local outcome="$2"
  local reason="$3"
  local secs="$4"
  if [ "$FINISHING" = "1" ]; then
    return 0
  fi
  FINISHING=1
  mkdir "$FINISHED_MARKER" 2>/dev/null || true

  if [ -n "$WATCHDOG_PID" ]; then
    stop_watchdog "$WATCHDOG_PID"
    WATCHDOG_PID=""
  fi

  # Take one final sample before killing descendants. On ordinary exit this
  # captures workers that remain in the target process group; on a cap/timeout
  # path it records the observed breach rather than an invented zero.
  sample_resources

  if [ "$outcome" = "exit" ]; then
    kill_child_briefly "$PID"
    dump_captured_output
    if [ "$exit_code" -eq 139 ]; then log_line "[CRASH] Segfault (exit 139)"; fi
    if [ "$exit_code" -eq 134 ]; then log_line "[CRASH] Abort (exit 134)"; fi
    log_line "[EXIT: $exit_code] after ~${secs}s"
  else
    case "$reason" in
      fd)
        log_line "[KILL] FD leak detected: ${CURRENT_FD_COUNT:-${MAX_FD:-?}} FDs after ~${secs}s"
        ;;
      memory)
        log_line "[KILL] Memory limit: ${CURRENT_RSS_KB:-${MAX_RSS_KB:-?}}KB > ${MAX_MEM}MB after ~${secs}s"
        ;;
      timeout)
        log_line "[KILL] Timeout after ${TIMEOUT}s (FDs: ${CURRENT_FD_COUNT:-${MAX_FD:-?}}, RSS: ${CURRENT_RSS_KB:-${MAX_RSS_KB:-?}}KB)"
        ;;
      *)
        log_line "[KILL] Signal termination (exit $exit_code)"
        ;;
    esac
    kill_child_briefly "$PID"
    dump_captured_output
  fi

  emit_resource_line "$outcome" "$exit_code" "$reason"
  exit "$exit_code"
}

handle_signal() {
  local exit_code="$1"
  local reason="signal"
  if [ -f "$WATCHDOG_REASON_FILE" ]; then
    reason=$(sed -n '1p' "$WATCHDOG_REASON_FILE" 2>/dev/null || true)
  fi
  finish "$exit_code" "killed" "$reason" "$((HALF_SECS / 2))"
}

trap cleanup EXIT
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

detect_resource_tools

# Give every supervised target its own group. Parent supervisors recurse over
# descendants before killing, so nested target groups remain reachable without
# sharing a kill group with their wrapper.
set -m
if [ "$PASSTHROUGH_STDIO" = "1" ]; then
  "$BINARY" "$@" <&0 >&1 2> "$STDERR_TMP" &
else
  "$BINARY" "$@" > "$STDOUT_TMP" 2> "$STDERR_TMP" &
fi
PID=$!
set +m
# `set -m` creates the background target as the leader of a new process group.
# Do not probe that fact through `ps`: sandboxed spec runners can deny `ps`,
# silently disabling group cleanup exactly where nested supervisors need it.
TARGET_PGID="$PID"
RUN_SAFE_PID=$$
export RUN_SAFE_TARGET_PID="$PID"

(
  # Fire slightly after the normal monitor timeout. This watchdog is only a
  # backstop for blocked probes/waits, not the primary timeout path.
  # The sleep must not inherit the caller's capture pipes. Otherwise killing
  # the watchdog shell leaves an orphan that keeps Process.run waiting until
  # the full timeout.
  sleep $((TIMEOUT + 2)) </dev/null >/dev/null 2>&1 &
  WATCHDOG_SLEEP_PID=$!
  printf '%s\n' "$WATCHDOG_SLEEP_PID" >"$WATCHDOG_SLEEP_FILE"
  wait "$WATCHDOG_SLEEP_PID" 2>/dev/null || true
  # Claim the watchdog path atomically. The parent creates FINISHED_MARKER
  # before normal completion, so a late watchdog cannot race a success report.
  if [ ! -e "$FINISHED_MARKER" ] && kill -0 "$PID" 2>/dev/null && mkdir "$WATCHDOG_MARKER" 2>/dev/null; then
    printf '%s\n' timeout >"$WATCHDOG_REASON_FILE"
    kill -TERM "$RUN_SAFE_PID" 2>/dev/null || true
  fi
) &
WATCHDOG_PID=$!

# Monitor loop (0.5s granularity)
HALF_SECS=0
MAX_HALF_SECS=$((TIMEOUT * 2))
while [ $HALF_SECS -lt $MAX_HALF_SECS ]; do
  if ! kill -0 "$PID" 2>/dev/null; then
    wait "$PID"
    EXIT=$?
    SECS=$((HALF_SECS / 2))
    finish "$EXIT" "exit" "exit" "$SECS"
  fi

  sample_resources

  if is_uint "$CURRENT_FD_COUNT" && [ "$CURRENT_FD_COUNT" -gt 1000 ]; then
    SECS=$((HALF_SECS / 2))
    finish 1 "killed" "fd" "$SECS"
  fi

  if is_uint "$CURRENT_RSS_KB" && [ "$CURRENT_RSS_KB" -gt $((MAX_MEM * 1024)) ]; then
    SECS=$((HALF_SECS / 2))
    finish 1 "killed" "memory" "$SECS"
  fi

  sleep 0.5
  HALF_SECS=$((HALF_SECS + 1))
done

# Timeout
finish 1 "killed" "timeout" "$((HALF_SECS / 2))"
