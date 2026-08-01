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
RESOURCE_EVIDENCE_FILE="${RUN_SAFE_RESOURCE_FILE:-}"
# The supervised target must not inherit the producer-owned evidence path.
# The wrapper publishes that file only after the target has stopped.
unset RUN_SAFE_RESOURCE_FILE
RUN_SAFE_SUPERVISOR_PID=$$
export RUN_SAFE_SUPERVISOR_PID

# Resource evidence is sampled from the supervised rooted ancestry. A missing or
# unusable probe remains explicitly unknown; an empty string must never be
# interpreted as zero by a cap check or by the final machine-readable line.
RSS_AVAILABLE="unknown"
FD_AVAILABLE="unknown"
PS_SNAPSHOT_AVAILABLE="unknown"
FD_TOPOLOGY_STABLE_SAMPLES=0
FD_TOPOLOGY_UNSTABLE_SAMPLES=0
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
RESOURCE_EVIDENCE_TMP=""

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

prepare_resource_evidence_file() {
  [ -n "$RESOURCE_EVIDENCE_FILE" ] || return 0
  case "$RESOURCE_EVIDENCE_FILE" in
    *$'\n'*) echo "error: RUN_SAFE_RESOURCE_FILE must be one path" >&2; exit 2 ;;
    /*) ;;
    *) echo "error: RUN_SAFE_RESOURCE_FILE must be absolute" >&2; exit 2 ;;
  esac
  if [ -e "$RESOURCE_EVIDENCE_FILE" ] || [ -L "$RESOURCE_EVIDENCE_FILE" ]; then
    echo "error: RUN_SAFE_RESOURCE_FILE already exists" >&2
    exit 2
  fi
  RESOURCE_EVIDENCE_TMP=$(mktemp "${RESOURCE_EVIDENCE_FILE}.tmp.XXXXXX") || {
    echo "error: cannot create RUN_SAFE_RESOURCE_FILE temporary" >&2
    exit 2
  }
}

validate_ps_table() {
  printf '%s\n' "$1" | awk -v root="$2" '
    NF != 4 { exit 1 }
    $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ { exit 1 }
    seen[$1]++ > 0 { exit 1 }
    $1 == root { found_root=1 }
    END { if (!found_root) exit 1 }
  '
}

capture_tree_snapshot() {
  local ps_table
  local tree_rows
  bounded_capture ps -axo pid=,ppid=,pgid=,rss= || return 1
  ps_table="$CAPTURE_OUTPUT"
  [ -n "$ps_table" ] || return 1
  validate_ps_table "$ps_table" "$PID" || return 1
  tree_rows=$(printf '%s\n' "$ps_table" | awk -v root="$PID" '
    {
      pid[NR] = $1
      ppid[NR] = $2
      pgid[NR] = $3
      rss[NR] = $4
      row_for_pid[$1] = NR
      count = NR
    }
    END {
      if (!(root in row_for_pid)) exit 1
      found[root] = 1
      changed = 1
      while (changed) {
        changed = 0
        for (i = 1; i <= count; i++) {
          if (!found[pid[i]] && found[ppid[i]]) {
            found[pid[i]] = 1
            changed = 1
          }
        }
      }
      for (i = 1; i <= count; i++) {
        if (found[pid[i]]) print pid[i], ppid[i], pgid[i], rss[i]
      }
    }
  ' | sort -n -k1,1) || return 1
  [ -n "$tree_rows" ] || return 1

  SNAPSHOT_SIGNATURE=$(printf '%s\n' "$tree_rows" | awk '{ printf "%s:%s:%s;", $1, $2, $3 }')
  SNAPSHOT_PIDS=$(printf '%s\n' "$tree_rows" | awk '{ if (NR > 1) printf ","; printf "%s", $1 }')
  SNAPSHOT_PID_COUNT=$(printf '%s\n' "$tree_rows" | awk 'END { print NR + 0 }')
  SNAPSHOT_RSS_KB=$(printf '%s\n' "$tree_rows" | awk '{ total += $4 } END { print total + 0 }')
  is_uint "$SNAPSHOT_PID_COUNT" && [ "$SNAPSHOT_PID_COUNT" -gt 0 ] || return 1
  is_uint "$SNAPSHOT_RSS_KB" || return 1
}

detect_resource_tools() {
  local saved_pid="$PID"
  PID="$$"
  if command -v ps >/dev/null 2>&1 && capture_tree_snapshot; then
    PS_SNAPSHOT_AVAILABLE="yes"
    RSS_AVAILABLE="yes"
  fi
  PID="$saved_pid"
  if command -v lsof >/dev/null 2>&1 && probe_lsof; then
    FD_AVAILABLE="yes"
  fi
}

probe_lsof() {
  local count
  bounded_capture lsof -n -P -F pf -p "$$" || return 1
  count=$(validated_lsof_count "$$" "$CAPTURE_OUTPUT") || return 1
  is_uint "$count"
}

validated_lsof_count() {
  local expected_csv="$1"
  local output="$2"
  printf '%s\n' "$output" | awk -v expected_csv="$expected_csv" '
    BEGIN {
      n = split(expected_csv, expected, ",")
      for (i = 1; i <= n; i++) wanted[expected[i]] = 1
    }
    /^p[0-9]+$/ {
      current = substr($0, 2)
      if (!wanted[current] || seen[current]) bad = 1
      seen[current] = 1
      next
    }
    /^f/ {
      if (current == "") bad = 1
      if ($0 !~ /^f([0-9]+[[:alpha:]]?|cwd|err|jld|ltx|M[0-9]+|m86|mem|mmap|pd|rtd|tr|txt|v86)$/) {
        bad = 1
      } else {
        fd_count++
      }
      next
    }
    NF != 0 { bad = 1 }
    END {
      for (pid in wanted) if (!seen[pid]) bad = 1
      if (bad || fd_count == 0) exit 1
      print fd_count + 0
    }
  '
}

fd_count_for_pids() {
  local pid_csv="$1"
  bounded_capture lsof -n -P -F pf -p "$pid_csv" || return 1
  validated_lsof_count "$pid_csv" "$CAPTURE_OUTPUT"
}

sample_resources() {
  if ! is_uint "$PID"; then
    return 0
  fi

  CURRENT_RSS_KB=""
  CURRENT_FD_COUNT=""
  TREE_SAMPLES=$((TREE_SAMPLES + 1))
  local before_signature=""
  local before_pids=""
  local before_pid_count=0
  local before_rss=""
  local fd_count=""

  if [ "$PS_SNAPSHOT_AVAILABLE" != "yes" ] || ! capture_tree_snapshot; then
    FD_TOPOLOGY_UNSTABLE_SAMPLES=$((FD_TOPOLOGY_UNSTABLE_SAMPLES + 1))
    return 0
  fi
  before_signature="$SNAPSHOT_SIGNATURE"
  before_pids="$SNAPSHOT_PIDS"
  before_pid_count="$SNAPSHOT_PID_COUNT"
  before_rss="$SNAPSHOT_RSS_KB"
  CURRENT_RSS_KB="$before_rss"
  RSS_SAMPLES=$((RSS_SAMPLES + 1))
  if [ -z "$MAX_RSS_KB" ] || [ "$before_rss" -gt "$MAX_RSS_KB" ]; then
    MAX_RSS_KB="$before_rss"
  fi
  if [ "$before_pid_count" -gt "$MAX_TREE_PIDS" ]; then
    MAX_TREE_PIDS="$before_pid_count"
  fi
  if [ "$FD_AVAILABLE" = "yes" ]; then
    fd_count=$(fd_count_for_pids "$before_pids" 2>/dev/null || true)
  fi
  if ! capture_tree_snapshot || [ "$SNAPSHOT_SIGNATURE" != "$before_signature" ]; then
    FD_TOPOLOGY_UNSTABLE_SAMPLES=$((FD_TOPOLOGY_UNSTABLE_SAMPLES + 1))
    return 0
  fi

  FD_TOPOLOGY_STABLE_SAMPLES=$((FD_TOPOLOGY_STABLE_SAMPLES + 1))
  if is_uint "$fd_count"; then
    CURRENT_FD_COUNT="$fd_count"
    FD_SAMPLES=$((FD_SAMPLES + 1))
    if [ -z "$MAX_FD" ] || [ "$fd_count" -gt "$MAX_FD" ]; then
      MAX_FD="$fd_count"
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
  local process_tree_mode="ps_ancestry_snapshot"
  local tree_coverage="all_scheduled_snapshots"
  local fd_tree_coverage="all_stable_pairs"
  local resource_line
  if [ "$RSS_SAMPLES" -ne "$TREE_SAMPLES" ] || [ "$RSS_SAMPLES" -eq 0 ]; then
    tree_coverage="unknown"
    max_rss="unknown"
    rss_available="unknown"
  fi
  if [ "$FD_SAMPLES" -ne "$TREE_SAMPLES" ] || [ "$FD_SAMPLES" -eq 0 ]; then
    fd_tree_coverage="unknown"
    max_fd="unknown"
    fd_available="unknown"
  fi
  if [ "$tree_coverage" = "unknown" ] && [ "$fd_tree_coverage" = "unknown" ]; then
    process_tree_mode="unknown"
  fi

  # Keep this one-line, key=value format stable for bootstrap/report parsers.
  # RSS is summed across each valid ancestry snapshot and is measured in KB.
  # FD maxima additionally require an unchanged pair around an lsof response
  # that names every PID from the first snapshot.
  resource_line="[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=$outcome reason=$reason exit_code=$exit_code max_rss_kb=$max_rss max_fd=$max_fd rss_samples=$RSS_SAMPLES fd_samples=$FD_SAMPLES rss_available=$rss_available fd_available=$fd_available process_tree_mode=$process_tree_mode tree_coverage=$tree_coverage fd_tree_coverage=$fd_tree_coverage tree_samples=$TREE_SAMPLES fd_topology_stable_samples=$FD_TOPOLOGY_STABLE_SAMPLES fd_topology_unstable_samples=$FD_TOPOLOGY_UNSTABLE_SAMPLES max_tree_pids=$MAX_TREE_PIDS"
  log_line "$resource_line"
  if [ -n "$RESOURCE_EVIDENCE_TMP" ]; then
    printf '%s\n' "$resource_line" >"$RESOURCE_EVIDENCE_TMP"
    if ln -n "$RESOURCE_EVIDENCE_TMP" "$RESOURCE_EVIDENCE_FILE" 2>/dev/null; then
      rm -f "$RESOURCE_EVIDENCE_TMP"
      RESOURCE_EVIDENCE_TMP=""
    else
      log_line "[RUN_SAFE_EVIDENCE_ERROR] resource file was not published"
      return 1
    fi
  fi
  return 0
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
  if [ -n "$RESOURCE_EVIDENCE_TMP" ]; then
    rm -f "$RESOURCE_EVIDENCE_TMP"
  fi
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

  # Sample only while the root is alive. A successful short-lived target may
  # legitimately have no stable sample; sampling its dead PID would instead
  # invalidate earlier evidence for no useful reason.
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    sample_resources
  fi

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

  if ! emit_resource_line "$outcome" "$exit_code" "$reason"; then
    exit 2
  fi
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

prepare_resource_evidence_file
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
