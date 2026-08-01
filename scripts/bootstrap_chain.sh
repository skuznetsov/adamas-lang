#!/usr/bin/env bash
# Bootstrap ladder: stage1 = host Crystal builds adamas; stage2+ = previous
# binary builds adamas again (plain flags only — no --stats in the ladder).
#
# Usage (from repo root):
#   scripts/bootstrap_chain.sh [--stages N] [--host PATH] [--source PATH] [--out DIR]
#       [--timeout SEC] [--mem MB]
#
# Environment (defaults if flags omitted):
#   CRYSTAL_HOST   — host compiler for stage1 (default: crystal)
#   BOOTSTRAP_CHAIN_STAGES / BOOTSTRAP_CHAIN_SOURCE / BOOTSTRAP_CHAIN_OUT
#   BOOTSTRAP_TIMEOUT_SEC — run_safe compiler timeout for every stage (default 900)
#   BOOTSTRAP_MEM_MB      — run_safe compiler RSS cap for every stage (default 12288)
#   BOOTSTRAP_SMOKE_PLAIN_MEM_MB — RSS cap for plain smoke only (default 8192).
#       Plain smoke uses the full prelude; 1024MB triggers false OOM under run_safe.
#
# Stage1 uses:  scripts/run_safe.sh host timeout mem build SOURCE -o OUT/cv2_s1 --error-trace
# Stage2+:      scripts/run_safe.sh PREV timeout mem SOURCE -o OUT/cv2_sN
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

STAGES="${BOOTSTRAP_CHAIN_STAGES:-5}"
HOST_CRYSTAL="${CRYSTAL_HOST:-crystal}"
SOURCE_REL="${BOOTSTRAP_CHAIN_SOURCE:-src/adamas.cr}"
OUT_DIR="${BOOTSTRAP_CHAIN_OUT:-}"
TIMEOUT_SEC="${BOOTSTRAP_TIMEOUT_SEC:-900}"
MEM_MB="${BOOTSTRAP_MEM_MB:-12288}"
SMOKE_PLAIN_MEM_MB="${BOOTSTRAP_SMOKE_PLAIN_MEM_MB:-8192}"

usage() {
  cat <<'USAGE'
Bootstrap ladder (stage1 = host Crystal builds adamas; stage2+ = previous
binary builds adamas again). Plain self-host only — no --stats on the ladder.

Usage:
  scripts/bootstrap_chain.sh [--stages N] [--host PATH] [--source PATH] [--out DIR]
      [--timeout SEC] [--mem MB]

Environment (optional):
  CRYSTAL_HOST          Host compiler for stage1 (default: crystal)
  BOOTSTRAP_CHAIN_STAGES / BOOTSTRAP_CHAIN_SOURCE / BOOTSTRAP_CHAIN_OUT
  BOOTSTRAP_TIMEOUT_SEC run_safe compiler timeout for every stage (default: 900)
  BOOTSTRAP_MEM_MB      run_safe compiler RSS cap for every stage (default: 12288)
  BOOTSTRAP_SMOKE_PLAIN_MEM_MB  RSS cap for plain smoke only (default: 8192)

Stage1:  scripts/run_safe.sh host timeout mem build SOURCE -o OUT/cv2_s1 --error-trace
Stage2+: scripts/run_safe.sh PREV timeout mem SOURCE -o OUT/cv2_sN
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stages)
      STAGES="$2"
      shift 2
      ;;
    --host)
      HOST_CRYSTAL="$2"
      shift 2
      ;;
    --source)
      SOURCE_REL="$2"
      shift 2
      ;;
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SEC="$2"
      shift 2
      ;;
    --mem)
      MEM_MB="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ "$1" == -* ]]; then
        echo "error: unknown option: $1" >&2
        exit 1
      fi
      HOST_CRYSTAL="$1"
      shift
      ;;
  esac
done

if ! [[ "$STAGES" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --stages must be a positive integer" >&2
  exit 1
fi
if ! [[ "$TIMEOUT_SEC" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --timeout must be a positive integer" >&2
  exit 1
fi
if ! [[ "$MEM_MB" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --mem must be a positive integer" >&2
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="/tmp/adamas_bootstrap_chain_${USER:-user}_$$"
fi
if [[ -e "$OUT_DIR" || -L "$OUT_DIR" ]]; then
  echo "error: output directory must not already exist: $OUT_DIR" >&2
  exit 1
fi
OUT_PARENT="$(dirname "$OUT_DIR")"
OUT_LEAF="$(basename "$OUT_DIR")"
if [[ "$OUT_LEAF" == "." || "$OUT_LEAF" == ".." || ! -d "$OUT_PARENT" ]]; then
  echo "error: output directory parent must already exist: $OUT_PARENT" >&2
  exit 1
fi
OUT_PARENT="$(cd "$OUT_PARENT" && pwd -P)" || exit 1
OUT_DIR="$OUT_PARENT/$OUT_LEAF"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

CONTAMINATING_ENV_NAMES=""
SANITIZED_ENV_NAMES=""
for env_name in $(env | sed -n 's/=.*//p'); do
  case "$env_name" in
    ADAMAS_*|RUN_SAFE_PASSTHROUGH_STDIO|RUN_SAFE_RESOURCE_FILE|CRYSTAL_WORKERS)
      CONTAMINATING_ENV_NAMES+="${env_name} "
      ;;
    CC|CXX|CPPFLAGS|CFLAGS|CXXFLAGS|LDFLAGS|LIBRARY_PATH|CPATH|SDKROOT|MACOSX_DEPLOYMENT_TARGET|DYLD_*|LD_PRELOAD|RUBYOPT)
      SANITIZED_ENV_NAMES+="${env_name} "
      unset "$env_name"
      ;;
  esac
done
if [[ -n "$CONTAMINATING_ENV_NAMES" ]]; then
  echo "error: bootstrap control environment must be unset: ${CONTAMINATING_ENV_NAMES% }" >&2
  exit 1
fi

SOURCE_ABS="$REPO_ROOT/$SOURCE_REL"
NO_PRELUDE_ORACLE="$REPO_ROOT/regression_tests/combined/test_no_prelude_interpolation.cr"
SMOKE_SRC="$OUT_DIR/_smoke_puts42.cr"
MANIFEST="$OUT_DIR/bootstrap_chain.manifest"
CACHE_DIR="$OUT_DIR/cache"

if [[ "$SOURCE_REL" == /* || -L "$SOURCE_ABS" ]]; then
  echo "error: source must be a non-symlink repository-relative path" >&2
  exit 1
fi
if [[ ! -f "$SOURCE_ABS" ]]; then
  echo "error: source not found: $SOURCE_ABS" >&2
  exit 1
fi
if [[ ! -f "$NO_PRELUDE_ORACLE" ]]; then
  echo "error: no-prelude oracle not found: $NO_PRELUDE_ORACLE" >&2
  exit 1
fi

REPO_REAL="$(cd "$REPO_ROOT" && pwd -P)"
SOURCE_DIR_REAL="$(cd "$(dirname "$SOURCE_ABS")" && pwd -P)"
case "$SOURCE_DIR_REAL/$(basename "$SOURCE_ABS")" in
  "$REPO_REAL"/*) ;;
  *) echo "error: source resolves outside repository" >&2; exit 1 ;;
esac
SOURCE_SCOPE_REL="${SOURCE_DIR_REAL#"$REPO_REAL"/}"
if [[ "$SOURCE_SCOPE_REL" == "$SOURCE_DIR_REAL" || "$SOURCE_SCOPE_REL" == "." ]]; then
  echo "error: source evidence scope must be a repository subdirectory" >&2
  exit 1
fi
SOURCE_SCOPE_REAL="$REPO_REAL/$SOURCE_SCOPE_REL"
case "$OUT_DIR" in
  "$SOURCE_SCOPE_REAL"|"$SOURCE_SCOPE_REAL"/*)
    echo "error: output directory must be outside source evidence scope" >&2
    exit 1
    ;;
esac
if [[ -n "$(find "$SOURCE_SCOPE_REAL" -type l -print -quit 2>/dev/null)" ]]; then
  echo "error: source evidence scope must not contain symlinks" >&2
  exit 1
fi
if ! (umask 077 && mkdir -- "$OUT_DIR") 2>/dev/null; then
  echo "error: unable to create fresh output directory: $OUT_DIR" >&2
  exit 1
fi
chmod 700 "$OUT_DIR" || exit 1

if command -v shasum >/dev/null 2>&1; then
  HASH_BACKEND="shasum"
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_BACKEND="sha256sum"
else
  echo "error: SHA-256 utility unavailable" >&2
  exit 1
fi

sha256_file() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  if [[ "$HASH_BACKEND" == "shasum" ]]; then
    shasum -a 256 -- "$path" | awk '{print $1}'
  else
    sha256sum -- "$path" | awk '{print $1}'
  fi
}

sha256_text() {
  if [[ "$HASH_BACKEND" == "shasum" ]]; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

hash_source_tree() {
  (
    cd "$REPO_ROOT" || exit 1
    if [[ "$HASH_BACKEND" == "shasum" ]]; then
      find "$SOURCE_SCOPE_REL" -type f -exec shasum -a 256 {} + 2>/dev/null | LC_ALL=C sort | shasum -a 256 | awk '{print $1}'
    else
      find "$SOURCE_SCOPE_REL" -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort | sha256sum | awk '{print $1}'
    fi
  )
}

resolve_tool_path() {
  local found
  if [[ "$1" == */* ]]; then
    found="$1"
  else
    found="$(command -v "$1" 2>/dev/null)" || return 1
  fi
  realpath "$found" 2>/dev/null || return 1
}

file_nlink() {
  stat -f '%l' "$1" 2>/dev/null || stat -c '%h' "$1" 2>/dev/null
}

directory_identity() {
  [[ -d "$1" && ! -L "$1" ]] || return 1
  stat -f '%d:%i' "$1" 2>/dev/null || stat -c '%d:%i' "$1" 2>/dev/null
}

directory_mode() {
  [[ -d "$1" && ! -L "$1" ]] || return 1
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}

valid_fresh_executable() {
  [[ -f "$1" && ! -L "$1" && -s "$1" && -x "$1" && "$(file_nlink "$1")" == "1" ]]
}

valid_evidence_file() {
  [[ -f "$1" && ! -L "$1" && -s "$1" && "$(file_nlink "$1")" == "1" ]]
}

HOST_COMPILER_RESOLVED="$(resolve_tool_path "$HOST_CRYSTAL")" || {
  echo "error: host compiler not found: $HOST_CRYSTAL" >&2
  exit 1
}
HOST_COMPILER_SHA256="$(sha256_file "$HOST_COMPILER_RESOLVED")" || {
  echo "error: host compiler must be a regular non-symlink file" >&2
  exit 1
}
SOURCE_CONTENT_SHA256_START="$(sha256_file "$SOURCE_ABS")" || exit 1
SOURCE_TREE_SHA256_START="$(hash_source_tree)" || exit 1
HARNESS_CHAIN_SHA256="$(sha256_file "$SCRIPT_DIR/bootstrap_chain.sh")" || exit 1
HARNESS_RUN_SAFE_SHA256="$(sha256_file "$SCRIPT_DIR/run_safe.sh")" || exit 1
GIT_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
SOURCE_GIT_STATUS="$(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all -- "$SOURCE_SCOPE_REL" 2>/dev/null || true)"
SOURCE_GIT_DIFF="$(git -C "$REPO_ROOT" diff --no-ext-diff --binary -- "$SOURCE_SCOPE_REL" 2>/dev/null || true)"
SOURCE_GIT_STATUS_SHA256="$(sha256_text "$SOURCE_GIT_STATUS")"
SOURCE_GIT_DIFF_SHA256="$(sha256_text "$SOURCE_GIT_DIFF")"
ENV_PATH_SHA256="$(sha256_text "${PATH:-}")"
ENV_HOME_SHA256="$(sha256_text "${HOME:-}")"
ENV_TMPDIR_SHA256="$(sha256_text "${TMPDIR:-/tmp}")"
SANITIZED_ENV_NAMES_SHA256="$(sha256_text "${SANITIZED_ENV_NAMES% }")"

mkdir "$CACHE_DIR" || exit 1
chmod 700 "$CACHE_DIR" || exit 1
OUT_DIR_ID_START="$(directory_identity "$OUT_DIR")" || exit 1
CACHE_DIR_ID_START="$(directory_identity "$CACHE_DIR")" || exit 1
if [[ "$(directory_mode "$OUT_DIR")" != "700" || "$(directory_mode "$CACHE_DIR")" != "700" ]]; then
  echo "error: bootstrap output and cache directories must be mode 700" >&2
  exit 1
fi
export CRYSTAL_CACHE_DIR="$CACHE_DIR"

cat > "$SMOKE_SRC" <<'EOF'
puts 42
EOF

parse_time_real() {
  local logfile="$1"
  # Portable time -p prints "real N.NN" and preserves the child exit status.
  # macOS time -l performs a kern.clockrate sysctl after the child exits; in a
  # sandbox that probe fails and changes an otherwise successful build to RC 1.
  awk '
    /^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 / { after_owned_resource = 1; real_count = 0; value = ""; next }
    after_owned_resource && $0 ~ /^real [0-9]+([.][0-9]+)?$/ { real_count++; value = $2 }
    END { if (real_count == 1) print value }
  ' "$logfile"
}

parse_time_l_max_rss_bytes() {
  local resource_file="$1"
  awk '
    /^\[RUN_SAFE_RESOURCE\]/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^max_rss_kb=/) {
          split($i, a, "=")
          if (a[2] ~ /^[0-9]+$/) print a[2] * 1024
        }
      }
    }
  ' "$resource_file"
}

resource_schema() {
  awk '
    /^\[RUN_SAFE_RESOURCE\]/ {
      rows++
      for (i = 1; i <= NF; i++) if ($i ~ /^schema=/) { split($i, a, "="); schema = a[2] }
    }
    END { if (NR == 1 && rows == 1) print schema }
  ' "$1"
}

resource_field() {
  local field="$1"
  local resource_file="$2"
  awk -v wanted="$field" '
    /^\[RUN_SAFE_RESOURCE\]/ {
      rows++
      for (i = 1; i <= NF; i++) {
        split($i, a, "=")
        if (a[1] == wanted) { count++; value = substr($i, length(wanted) + 2) }
      }
    }
    END { if (NR == 1 && rows == 1 && count == 1) print value }
  ' "$resource_file"
}

resource_success_contract() {
  local resource_file="$1"
  valid_evidence_file "$resource_file" &&
    [[ "$(resource_field schema "$resource_file")" == "run_safe_resource_v1" ]] &&
    [[ "$(resource_field outcome "$resource_file")" == "exit" ]] &&
    [[ "$(resource_field reason "$resource_file")" == "exit" ]] &&
    [[ "$(resource_field exit_code "$resource_file")" == "0" ]]
}

bytes_to_mb() {
  local b="$1"
  if [[ -z "$b" || "$b" == "0" ]]; then
    echo ""
    return
  fi
  awk -v n="$b" 'BEGIN { printf "%.2f", n / 1048576.0 }'
}

# Returns: exit code of build in $1; sets WALL_REAL, PEAK_MB, LOG
run_stage1_host() {
  local out_bin="$1"
  local logfile="$2"
  local resource_file="$3"
  (
    cd "$REPO_ROOT"
    RUN_SAFE_RESOURCE_FILE="$resource_file" /usr/bin/time -p "$SCRIPT_DIR/run_safe.sh" "$HOST_COMPILER_RESOLVED" "$TIMEOUT_SEC" "$MEM_MB" \
      build "$SOURCE_REL" -o "$out_bin" --error-trace
  ) >"$logfile" 2>&1
}

run_stageN_selfhost() {
  local compiler="$1"
  local out_bin="$2"
  local logfile="$3"
  local resource_file="$4"
  (
    cd "$REPO_ROOT"
    RUN_SAFE_RESOURCE_FILE="$resource_file" /usr/bin/time -p "$SCRIPT_DIR/run_safe.sh" "$compiler" "$TIMEOUT_SEC" "$MEM_MB" \
      "$SOURCE_REL" -o "$out_bin"
  ) >"$logfile" 2>&1
}

run_compiled_smoke() {
  local binary="$1"
  local marker="$2"
  local runtime_log="$3"

  if ! "$SCRIPT_DIR/run_safe.sh" "$binary" 10 512 >"$runtime_log" 2>&1; then
    cat "$runtime_log"
    return 1
  fi
  cat "$runtime_log"
  exact_smoke_transcript "$runtime_log" "$marker"
}

exact_smoke_transcript() {
  local runtime_log="$1"
  local marker="$2"
  local counts

  counts="$(awk -v wanted="$marker" '
    $0 == "=== STDOUT ===" { stdout_headers++; section = "stdout"; next }
    $0 == "=== STDERR ===" { stderr_headers++; section = "stderr"; next }
    /^\[EXIT: 0\] / { exit_rows++; section = ""; next }
    /^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 / { resource_rows++; next }
    section == "stdout" {
      stdout_lines++
      if ($0 == wanted) marker_count++; else wrong_stdout++
    }
    section == "stderr" { stderr_lines++ }
    END {
      print marker_count + 0, stdout_lines + 0, wrong_stdout + 0, stderr_lines + 0,
        stdout_headers + 0, stderr_headers + 0, exit_rows + 0, resource_rows + 0
    }
  ' "$runtime_log")"
  if [[ "$counts" != "1 1 0 0 1 1 1 1" ]]; then
    echo "error: smoke runtime transcript mismatch: log=$runtime_log marker=$marker counts=$counts" >&2
    return 1
  fi
}

run_smoke_plain() {
  local compiler="$1"
  local logfile="$2"
  local stage="$3"
  local binary="$OUT_DIR/stage${stage}_smoke_plain.bin"
  local runtime_log="$OUT_DIR/stage${stage}_smoke_plain.runtime.log"
  if [[ -e "$binary" || -L "$binary" || -e "$runtime_log" || -L "$runtime_log" ]]; then
    echo "error: smoke output path already exists" >&2
    return 1
  fi
  (
    cd "$REPO_ROOT"
    /usr/bin/time -p "$SCRIPT_DIR/run_safe.sh" "$compiler" 60 "$SMOKE_PLAIN_MEM_MB" \
      "$SMOKE_SRC" -o "$binary" || exit $?
    valid_fresh_executable "$binary" || exit 1
    run_compiled_smoke "$binary" "42" "$runtime_log"
  ) >"$logfile" 2>&1
}

run_smoke_noprelude() {
  local compiler="$1"
  local logfile="$2"
  local stage="$3"
  local binary="$OUT_DIR/stage${stage}_smoke_noprelude.bin"
  local runtime_log="$OUT_DIR/stage${stage}_smoke_noprelude.runtime.log"
  if [[ -e "$binary" || -L "$binary" || -e "$runtime_log" || -L "$runtime_log" ]]; then
    echo "error: smoke output path already exists" >&2
    return 1
  fi
  (
    cd "$REPO_ROOT"
    /usr/bin/time -p "$SCRIPT_DIR/run_safe.sh" "$compiler" 120 1024 \
      "$NO_PRELUDE_ORACLE" --no-prelude -o "$binary" || exit $?
    valid_fresh_executable "$binary" || exit 1
    run_compiled_smoke "$binary" "noprelude_interp_ok" "$runtime_log"
  ) >"$logfile" 2>&1
}

stderr_tail() {
  local logfile="$1"
  local n="${2:-80}"
  if [[ -f "$logfile" ]]; then
    echo "--- tail ($n lines): $logfile ---"
    tail -n "$n" "$logfile"
  fi
}

echo "=== Bootstrap chain ==="
echo "repo:       $REPO_ROOT"
echo "stages:     $STAGES"
echo "host (s1):  $HOST_CRYSTAL"
echo "source:     $SOURCE_REL"
echo "out dir:    $OUT_DIR"
echo "compiler run_safe: timeout=${TIMEOUT_SEC}s mem=${MEM_MB}MB"
echo "smoke plain run_safe: timeout=60s mem=${SMOKE_PLAIN_MEM_MB}MB (override BOOTSTRAP_SMOKE_PLAIN_MEM_MB)"
echo ""

declare -a ST_OK ST_BIN ST_WALL ST_PEAK ST_SMOKE_P ST_SMOKE_N ST_LOG
declare -a ST_PRODUCER_HASH ST_PRODUCER_HASH_END ST_OUTPUT_HASH ST_OUTPUT_HASH_END
declare -a ST_PRODUCER_MATCH ST_FLAGS_B64 ST_STARTED ST_FINISHED ST_RESOURCE_FILE
declare -a ST_RESOURCE_HASH ST_RESOURCE_SCHEMA ST_BUILD_LOG_HASH
declare -a ST_SMOKE_P_BIN_HASH ST_SMOKE_N_BIN_HASH ST_SMOKE_P_LOG_HASH ST_SMOKE_N_LOG_HASH
declare -a ST_SMOKE_P_COMPILE_LOG_HASH ST_SMOKE_N_COMPILE_LOG_HASH
FIRST_FAIL=""
FIRST_FAIL_KIND=""
FIRST_SYMPTOM=""

base64_value() {
  printf '%s' "$1" | base64 | tr -d '\r\n'
}

hash_matches() {
  local path="$1"
  local expected="$2"
  local kind="$3"
  local actual

  if [[ "$kind" == "executable" ]]; then
    valid_fresh_executable "$path" || return 1
  else
    valid_evidence_file "$path" || return 1
  fi
  actual="$(sha256_file "$path")" || return 1
  [[ "$actual" == "$expected" ]]
}

final_stage_evidence_valid() {
  local stage="$1"
  local producer
  if [[ "$stage" -eq 1 ]]; then
    producer="$HOST_COMPILER_RESOLVED"
  else
    producer="$OUT_DIR/cv2_s$((stage - 1))"
  fi

  [[ "$(sha256_file "$producer" 2>/dev/null || printf missing)" == "${ST_PRODUCER_HASH_END[$stage]}" ]] &&
    hash_matches "$OUT_DIR/cv2_s${stage}" "${ST_OUTPUT_HASH_END[$stage]}" executable &&
    hash_matches "$OUT_DIR/stage${stage}_build.log" "${ST_BUILD_LOG_HASH[$stage]}" evidence &&
    hash_matches "$OUT_DIR/stage${stage}_build.resource" "${ST_RESOURCE_HASH[$stage]}" evidence &&
    resource_success_contract "$OUT_DIR/stage${stage}_build.resource" &&
    hash_matches "$OUT_DIR/stage${stage}_smoke_plain.bin" "${ST_SMOKE_P_BIN_HASH[$stage]}" executable &&
    hash_matches "$OUT_DIR/stage${stage}_smoke_plain.log" "${ST_SMOKE_P_COMPILE_LOG_HASH[$stage]}" evidence &&
    hash_matches "$OUT_DIR/stage${stage}_smoke_plain.runtime.log" "${ST_SMOKE_P_LOG_HASH[$stage]}" evidence &&
    exact_smoke_transcript "$OUT_DIR/stage${stage}_smoke_plain.runtime.log" "42" &&
    hash_matches "$OUT_DIR/stage${stage}_smoke_noprelude.bin" "${ST_SMOKE_N_BIN_HASH[$stage]}" executable &&
    hash_matches "$OUT_DIR/stage${stage}_smoke_noprelude.log" "${ST_SMOKE_N_COMPILE_LOG_HASH[$stage]}" evidence &&
    hash_matches "$OUT_DIR/stage${stage}_smoke_noprelude.runtime.log" "${ST_SMOKE_N_LOG_HASH[$stage]}" evidence &&
    exact_smoke_transcript "$OUT_DIR/stage${stage}_smoke_noprelude.runtime.log" "noprelude_interp_ok"
}

write_manifest() {
  local manifest_status="$1"
  local tmp_manifest
  local stage
  if [[ -e "$MANIFEST" || -L "$MANIFEST" ]]; then
    echo "error: bootstrap manifest path already exists" >&2
    return 1
  fi
  tmp_manifest="$(mktemp "$MANIFEST.tmp.XXXXXX")" || return 1
  {
    echo "manifest_schema=bootstrap_chain_v3"
    echo "run_id=$RUN_ID"
    echo "run_started_at=$RUN_STARTED_AT"
    echo "run_finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "status=$manifest_status"
    echo "requested_stages=$STAGES"
    echo "recorded_stages=${#ST_OK[@]}"
    echo "failed_stage=${FIRST_FAIL:-none}"
    echo "failed_kind=${FIRST_FAIL_KIND:-none}"
    echo "source_rel_b64=$(base64_value "$SOURCE_REL")"
    echo "source_scope_rel_b64=$(base64_value "$SOURCE_SCOPE_REL")"
    echo "source_content_sha256_start=$SOURCE_CONTENT_SHA256_START"
    echo "source_content_sha256_end=$SOURCE_CONTENT_SHA256_END"
    echo "source_tree_sha256_start=$SOURCE_TREE_SHA256_START"
    echo "source_tree_sha256_end=$SOURCE_TREE_SHA256_END"
    echo "source_hash_consistent=$SOURCE_HASH_CONSISTENT"
    echo "source_git_head=$GIT_HEAD"
    echo "source_git_status_sha256=$SOURCE_GIT_STATUS_SHA256"
    echo "source_git_diff_sha256=$SOURCE_GIT_DIFF_SHA256"
    echo "source_consistency_model=endpoint_before_after"
    echo "host_compiler_b64=$(base64_value "$HOST_COMPILER_RESOLVED")"
    echo "host_compiler_sha256=$HOST_COMPILER_SHA256"
    echo "harness_bootstrap_chain_sha256=$HARNESS_CHAIN_SHA256"
    echo "harness_run_safe_sha256=$HARNESS_RUN_SAFE_SHA256"
    echo "environment_path_sha256=$ENV_PATH_SHA256"
    echo "environment_home_sha256=$ENV_HOME_SHA256"
    echo "environment_tmpdir_sha256=$ENV_TMPDIR_SHA256"
    echo "compiler_environment_policy=known_controls_unset"
    echo "compiler_environment_sanitized_names_sha256=$SANITIZED_ENV_NAMES_SHA256"
    echo "run_directory_policy=producer_created_absent_path"
    echo "run_directory_identity=$OUT_DIR_ID_START"
    echo "cache_policy=producer_created_empty"
    echo "cache_dir_rel=cache"
    echo "cache_directory_identity=$CACHE_DIR_ID_START"
    echo "worker_policy=crystal_workers_unset"
    for ((stage = 1; stage <= ${#ST_OK[@]}; stage++)); do
      echo "stage${stage}_status=${ST_OK[$((stage - 1))]}"
      echo "stage${stage}_build_mode=normal_binary"
      echo "stage${stage}_build_started_at=${ST_STARTED[$stage]:-unknown}"
      echo "stage${stage}_build_finished_at=${ST_FINISHED[$stage]:-unknown}"
      echo "stage${stage}_build_wall_sec=${ST_WALL[$((stage - 1))]:-unknown}"
      echo "stage${stage}_flags_b64=${ST_FLAGS_B64[$stage]:-}"
      echo "stage${stage}_producer_sha256=${ST_PRODUCER_HASH[$stage]:-missing}"
      echo "stage${stage}_producer_sha256_end=${ST_PRODUCER_HASH_END[$stage]:-missing}"
      echo "stage${stage}_producer_matches_previous_output=${ST_PRODUCER_MATCH[$stage]:-unknown}"
      echo "stage${stage}_output_rel=cv2_s${stage}"
      echo "stage${stage}_output_sha256=${ST_OUTPUT_HASH[$stage]:-missing}"
      echo "stage${stage}_output_sha256_end=${ST_OUTPUT_HASH_END[$stage]:-missing}"
      echo "stage${stage}_build_log_rel=stage${stage}_build.log"
      echo "stage${stage}_build_log_sha256=${ST_BUILD_LOG_HASH[$stage]:-missing}"
      echo "stage${stage}_resource_rel=stage${stage}_build.resource"
      echo "stage${stage}_resource_sha256=${ST_RESOURCE_HASH[$stage]:-missing}"
      echo "stage${stage}_resource_schema=${ST_RESOURCE_SCHEMA[$stage]:-missing}"
      echo "stage${stage}_smoke_plain_status=${ST_SMOKE_P[$((stage - 1))]:--}"
      echo "stage${stage}_smoke_plain_expected=42"
      echo "stage${stage}_smoke_plain_binary_rel=stage${stage}_smoke_plain.bin"
      echo "stage${stage}_smoke_plain_compile_log_rel=stage${stage}_smoke_plain.log"
      echo "stage${stage}_smoke_plain_runtime_log_rel=stage${stage}_smoke_plain.runtime.log"
      echo "stage${stage}_smoke_plain_binary_sha256=${ST_SMOKE_P_BIN_HASH[$stage]:-missing}"
      echo "stage${stage}_smoke_plain_compile_log_sha256=${ST_SMOKE_P_COMPILE_LOG_HASH[$stage]:-missing}"
      echo "stage${stage}_smoke_plain_log_sha256=${ST_SMOKE_P_LOG_HASH[$stage]:-missing}"
      echo "stage${stage}_smoke_noprelude_status=${ST_SMOKE_N[$((stage - 1))]:--}"
      echo "stage${stage}_smoke_noprelude_expected=noprelude_interp_ok"
      echo "stage${stage}_smoke_noprelude_binary_rel=stage${stage}_smoke_noprelude.bin"
      echo "stage${stage}_smoke_noprelude_compile_log_rel=stage${stage}_smoke_noprelude.log"
      echo "stage${stage}_smoke_noprelude_runtime_log_rel=stage${stage}_smoke_noprelude.runtime.log"
      echo "stage${stage}_smoke_noprelude_binary_sha256=${ST_SMOKE_N_BIN_HASH[$stage]:-missing}"
      echo "stage${stage}_smoke_noprelude_compile_log_sha256=${ST_SMOKE_N_COMPILE_LOG_HASH[$stage]:-missing}"
      echo "stage${stage}_smoke_noprelude_log_sha256=${ST_SMOKE_N_LOG_HASH[$stage]:-missing}"
    done
  } >"$tmp_manifest" || {
    rm -f "$tmp_manifest"
    return 1
  }
  if ! ln -n "$tmp_manifest" "$MANIFEST" 2>/dev/null; then
    rm -f "$tmp_manifest"
    echo "error: unable to publish bootstrap manifest" >&2
    return 1
  fi
  rm -f "$tmp_manifest"
}

for ((s = 1; s <= STAGES; s++)); do
  OUT_BIN="$OUT_DIR/cv2_s${s}"
  LOG_B="$OUT_DIR/stage${s}_build.log"
  LOG_P="$OUT_DIR/stage${s}_smoke_plain.log"
  LOG_N="$OUT_DIR/stage${s}_smoke_noprelude.log"
  RESOURCE_B="$OUT_DIR/stage${s}_build.resource"

  ST_STARTED[$s]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ST_RESOURCE_FILE[$s]="$RESOURCE_B"
  ST_OUTPUT_HASH[$s]="missing"
  ST_OUTPUT_HASH_END[$s]="missing"
  ST_RESOURCE_HASH[$s]="missing"
  ST_RESOURCE_SCHEMA[$s]="missing"
  ST_BUILD_LOG_HASH[$s]="missing"
  ST_SMOKE_P_BIN_HASH[$s]="missing"
  ST_SMOKE_N_BIN_HASH[$s]="missing"
  ST_SMOKE_P_LOG_HASH[$s]="missing"
  ST_SMOKE_N_LOG_HASH[$s]="missing"
  ST_SMOKE_P_COMPILE_LOG_HASH[$s]="missing"
  ST_SMOKE_N_COMPILE_LOG_HASH[$s]="missing"

  if [[ $s -eq 1 ]]; then
    PRODUCER="$HOST_COMPILER_RESOLVED"
    ST_PRODUCER_MATCH[$s]="not_applicable"
    ST_FLAGS_B64[$s]="$(base64_value "build $SOURCE_REL -o cv2_s${s} --error-trace")"
  else
    PRODUCER="$PREV"
    ST_FLAGS_B64[$s]="$(base64_value "$SOURCE_REL -o cv2_s${s}")"
  fi
  ST_PRODUCER_HASH[$s]="$(sha256_file "$PRODUCER" 2>/dev/null || printf 'missing')"
  if [[ $s -gt 1 ]]; then
    if [[ "${ST_PRODUCER_HASH[$s]}" == "${ST_OUTPUT_HASH_END[$((s - 1))]:-}" ]]; then
      ST_PRODUCER_MATCH[$s]="yes"
    else
      ST_PRODUCER_MATCH[$s]="no"
    fi
  fi

  if [[ -e "$OUT_BIN" || -L "$OUT_BIN" || -e "$LOG_B" || -L "$LOG_B" || -e "$RESOURCE_B" || -L "$RESOURCE_B" ]]; then
    ST_FINISHED[$s]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ST_PRODUCER_HASH_END[$s]="${ST_PRODUCER_HASH[$s]}"
    ST_OK+=("fail")
    ST_BIN+=("$OUT_BIN")
    ST_WALL+=("unknown")
    ST_PEAK+=("?")
    ST_SMOKE_P+=("-")
    ST_SMOKE_N+=("-")
    ST_LOG+=("$LOG_B")
    FIRST_FAIL="$s"
    FIRST_FAIL_KIND="stale_output"
    FIRST_SYMPTOM="stage output path already exists before producer launch"
    echo "error: stage output path already exists before producer launch: $OUT_BIN" >&2
    break
  fi

  if [[ $s -gt 1 && "${ST_PRODUCER_MATCH[$s]}" != "yes" ]]; then
    ST_FINISHED[$s]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ST_PRODUCER_HASH_END[$s]="${ST_PRODUCER_HASH[$s]}"
    ST_OK+=("fail")
    ST_BIN+=("$OUT_BIN")
    ST_WALL+=("unknown")
    ST_PEAK+=("?")
    ST_SMOKE_P+=("-")
    ST_SMOKE_N+=("-")
    ST_LOG+=("$LOG_B")
    FIRST_FAIL="$s"
    FIRST_FAIL_KIND="producer_lineage"
    FIRST_SYMPTOM="stage producer hash does not match previous output"
    break
  fi

  if [[ $s -eq 1 ]]; then
    echo "--- Stage $s (host build) ---"
    run_stage1_host "$OUT_BIN" "$LOG_B" "$RESOURCE_B"
    RC=$?
    PREV="$OUT_BIN"
  else
    echo "--- Stage $s (self-host via cv2_s$((s - 1))) ---"
    run_stageN_selfhost "$PREV" "$OUT_BIN" "$LOG_B" "$RESOURCE_B"
    RC=$?
    PREV="$OUT_BIN"
  fi

  ST_FINISHED[$s]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ST_PRODUCER_HASH_END[$s]="$(sha256_file "$PRODUCER" 2>/dev/null || printf 'missing')"
  ST_BUILD_LOG_HASH[$s]="$(sha256_file "$LOG_B" 2>/dev/null || printf 'missing')"
  if valid_evidence_file "$RESOURCE_B"; then
    ST_RESOURCE_HASH[$s]="$(sha256_file "$RESOURCE_B" 2>/dev/null || printf 'missing')"
    ST_RESOURCE_SCHEMA[$s]="$(resource_schema "$RESOURCE_B" 2>/dev/null || true)"
  fi
  WALL_REAL="$(parse_time_real "$LOG_B" || true)"
  RSS_B="$(parse_time_l_max_rss_bytes "$RESOURCE_B" 2>/dev/null || true)"
  PEAK_MB="$(bytes_to_mb "$RSS_B")"

  if [[ $RC -eq 0 ]] && ! resource_success_contract "$RESOURCE_B"; then
    RC=1
    FIRST_FAIL="$s"
    FIRST_FAIL_KIND="resource_evidence"
    FIRST_SYMPTOM="missing or invalid successful producer-owned run_safe resource receipt"
  fi
  if [[ $RC -eq 0 ]] && ! valid_evidence_file "$LOG_B"; then
    RC=1
    FIRST_FAIL="$s"
    FIRST_FAIL_KIND="build_log_evidence"
    FIRST_SYMPTOM="missing, symlinked, empty, or hardlinked build log"
  fi
  if [[ $RC -eq 0 && ! "$WALL_REAL" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    RC=1
    FIRST_FAIL="$s"
    FIRST_FAIL_KIND="build_time_evidence"
    FIRST_SYMPTOM="missing or malformed build wall time"
  fi

  if [[ $RC -ne 0 ]]; then
    ST_OK+=("fail")
    ST_BIN+=("$OUT_BIN")
    ST_WALL+=("${WALL_REAL:-?}")
    ST_PEAK+=("${PEAK_MB:-?}")
    ST_SMOKE_P+=("-")
    ST_SMOKE_N+=("-")
    ST_LOG+=("$LOG_B")
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="${FIRST_FAIL_KIND:-build}"
      FIRST_SYMPTOM="$(stderr_tail "$LOG_B" 40)"
    fi
    echo "STAGE $s BUILD: FAIL (exit $RC)"
    stderr_tail "$LOG_B" 50
    break
  fi

  if ! valid_fresh_executable "$OUT_BIN"; then
    ST_OK+=("fail")
    ST_BIN+=("$OUT_BIN")
    ST_WALL+=("${WALL_REAL:-?}")
    ST_PEAK+=("${PEAK_MB:-?}")
    ST_SMOKE_P+=("-")
    ST_SMOKE_N+=("-")
    ST_LOG+=("$LOG_B")
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="missing_binary"
      FIRST_SYMPTOM="fresh stage executable missing, empty, symlinked, or hardlinked: $OUT_BIN"
    fi
    echo "STAGE $s: fresh stage executable contract failed"
    break
  fi

  ST_OUTPUT_HASH[$s]="$(sha256_file "$OUT_BIN")"
  echo "STAGE $s BUILD: ok  wall=${WALL_REAL:-?}s  peak_rss≈${PEAK_MB:-?}MB  -> $OUT_BIN"

  SP_OK="ok"
  SN_OK="ok"
  run_smoke_plain "$OUT_BIN" "$LOG_P" "$s"
  RCP=$?
  if [[ $RCP -ne 0 ]]; then
    SP_OK="fail"
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="smoke_plain"
      FIRST_SYMPTOM="$(stderr_tail "$LOG_P" 40)"
    fi
  fi
  run_smoke_noprelude "$OUT_BIN" "$LOG_N" "$s"
  RCN=$?
  if [[ $RCN -ne 0 ]]; then
    SN_OK="fail"
    if [[ -z "$FIRST_FAIL" ]]; then
      FIRST_FAIL="$s"
      FIRST_FAIL_KIND="smoke_noprelude"
      FIRST_SYMPTOM="$(stderr_tail "$LOG_N" 40)"
    fi
  fi
  if [[ "$SP_OK" == "ok" ]] && { ! valid_evidence_file "$LOG_P" || ! valid_evidence_file "$OUT_DIR/stage${s}_smoke_plain.runtime.log"; }; then
    SP_OK="fail"
    FIRST_FAIL="${FIRST_FAIL:-$s}"
    FIRST_FAIL_KIND="${FIRST_FAIL_KIND:-smoke_plain_evidence}"
    FIRST_SYMPTOM="${FIRST_SYMPTOM:-plain smoke evidence file contract failed}"
  fi
  if [[ "$SN_OK" == "ok" ]] && { ! valid_evidence_file "$LOG_N" || ! valid_evidence_file "$OUT_DIR/stage${s}_smoke_noprelude.runtime.log"; }; then
    SN_OK="fail"
    FIRST_FAIL="${FIRST_FAIL:-$s}"
    FIRST_FAIL_KIND="${FIRST_FAIL_KIND:-smoke_noprelude_evidence}"
    FIRST_SYMPTOM="${FIRST_SYMPTOM:-no-prelude smoke evidence file contract failed}"
  fi

  if [[ "$SP_OK" == "ok" && "$SN_OK" == "ok" ]]; then
    ST_OK+=("ok")
  else
    ST_OK+=("fail")
  fi
  ST_BIN+=("$OUT_BIN")
  ST_WALL+=("${WALL_REAL:-?}")
  ST_PEAK+=("${PEAK_MB:-?}")
  ST_SMOKE_P+=("$SP_OK")
  ST_SMOKE_N+=("$SN_OK")
  ST_LOG+=("$LOG_B")
  ST_SMOKE_P_BIN_HASH[$s]="$(sha256_file "$OUT_DIR/stage${s}_smoke_plain.bin" 2>/dev/null || printf 'missing')"
  ST_SMOKE_N_BIN_HASH[$s]="$(sha256_file "$OUT_DIR/stage${s}_smoke_noprelude.bin" 2>/dev/null || printf 'missing')"
  ST_SMOKE_P_LOG_HASH[$s]="$(sha256_file "$OUT_DIR/stage${s}_smoke_plain.runtime.log" 2>/dev/null || printf 'missing')"
  ST_SMOKE_N_LOG_HASH[$s]="$(sha256_file "$OUT_DIR/stage${s}_smoke_noprelude.runtime.log" 2>/dev/null || printf 'missing')"
  ST_SMOKE_P_COMPILE_LOG_HASH[$s]="$(sha256_file "$LOG_P" 2>/dev/null || printf 'missing')"
  ST_SMOKE_N_COMPILE_LOG_HASH[$s]="$(sha256_file "$LOG_N" 2>/dev/null || printf 'missing')"

  echo "  smoke plain:     $SP_OK"
  echo "  smoke no-prelude: $SN_OK"
  if [[ "$SP_OK" != "ok" ]]; then
    stderr_tail "$LOG_P" 30
  fi
  if [[ "$SN_OK" != "ok" ]]; then
    stderr_tail "$LOG_N" 30
  fi

  if [[ "$SP_OK" != "ok" || "$SN_OK" != "ok" ]]; then
    break
  fi

  ST_PRODUCER_HASH_END[$s]="$(sha256_file "$PRODUCER" 2>/dev/null || printf 'missing')"
  ST_OUTPUT_HASH_END[$s]="$(sha256_file "$OUT_BIN" 2>/dev/null || printf 'missing')"
  if [[ "${ST_PRODUCER_HASH_END[$s]}" != "${ST_PRODUCER_HASH[$s]}" || "${ST_OUTPUT_HASH_END[$s]}" != "${ST_OUTPUT_HASH[$s]}" ]]; then
    ST_OK[$((${#ST_OK[@]} - 1))]="fail"
    FIRST_FAIL="$s"
    FIRST_FAIL_KIND="artifact_mutated"
    FIRST_SYMPTOM="producer or stage output changed during smoke verification"
    break
  fi
done

for ((s = 1; s <= ${#ST_OK[@]}; s++)); do
  if [[ "${ST_OK[$((s - 1))]}" == "ok" ]] && ! final_stage_evidence_valid "$s"; then
    ST_OK[$((s - 1))]="fail"
    FIRST_FAIL="${FIRST_FAIL:-$s}"
    FIRST_FAIL_KIND="${FIRST_FAIL_KIND:-evidence_mutated}"
    FIRST_SYMPTOM="${FIRST_SYMPTOM:-evidence changed before manifest publication}"
    break
  fi
done

SOURCE_CONTENT_SHA256_END="$(sha256_file "$SOURCE_ABS" 2>/dev/null || printf 'missing')"
SOURCE_TREE_SHA256_END="$(hash_source_tree 2>/dev/null || printf 'missing')"
OUT_DIR_ID_END="$(directory_identity "$OUT_DIR" 2>/dev/null || printf 'missing')"
CACHE_DIR_ID_END="$(directory_identity "$CACHE_DIR" 2>/dev/null || printf 'missing')"
if [[ "$SOURCE_CONTENT_SHA256_END" == "$SOURCE_CONTENT_SHA256_START" &&
      "$SOURCE_TREE_SHA256_END" == "$SOURCE_TREE_SHA256_START" &&
      -z "$(find "$SOURCE_SCOPE_REAL" -type l -print -quit 2>/dev/null)" ]]; then
  SOURCE_HASH_CONSISTENT=1
else
  SOURCE_HASH_CONSISTENT=0
  if [[ -z "$FIRST_FAIL" ]]; then
    FIRST_FAIL="source"
    FIRST_FAIL_KIND="source_mutated"
    FIRST_SYMPTOM="bootstrap source scope changed during the run"
  fi
fi
if [[ "$OUT_DIR_ID_END" != "$OUT_DIR_ID_START" ||
      "$CACHE_DIR_ID_END" != "$CACHE_DIR_ID_START" ||
      "$(directory_mode "$OUT_DIR" 2>/dev/null || printf missing)" != "700" ||
      "$(directory_mode "$CACHE_DIR" 2>/dev/null || printf missing)" != "700" ]]; then
  if [[ -z "$FIRST_FAIL" ]]; then
    FIRST_FAIL="context"
    FIRST_FAIL_KIND="directory_identity"
    FIRST_SYMPTOM="producer-owned output or cache directory identity changed"
  fi
fi

echo ""
echo "================================================================"
echo "SUMMARY"
echo "================================================================"

printf "%-6s %-8s %-10s %-12s %-12s %-12s %s\n" \
  "Stage" "Build" "Wall(s)" "PeakRSS(MB)" "Smoke+" "SmokeNP" "Binary"
for ((i = 0; i < ${#ST_OK[@]}; i++)); do
  sn=$((i + 1))
  printf "%-6s %-8s %-10s %-12s %-12s %-12s %s\n" \
    "s${sn}" "${ST_OK[$i]}" "${ST_WALL[$i]}" "${ST_PEAK[$i]}" "${ST_SMOKE_P[$i]}" "${ST_SMOKE_N[$i]}" "${ST_BIN[$i]}"
done

echo ""
FINAL_STATUS="failed"
if [[ -z "$FIRST_FAIL" && ${#ST_OK[@]} -eq "$STAGES" ]]; then
  LAST_IDX=$((${#ST_OK[@]} - 1))
  if [[ "${ST_OK[$LAST_IDX]:-}" == "ok" ]]; then
    FINAL_STATUS="success"
  fi
fi

if ! write_manifest "$FINAL_STATUS"; then
  echo "error: bootstrap provenance manifest was not published" >&2
  exit 1
fi
echo "manifest: $MANIFEST"

if [[ "$FINAL_STATUS" != "success" ]]; then
  if [[ -z "$FIRST_FAIL" ]]; then
    FIRST_FAIL="incomplete"
    FIRST_FAIL_KIND="incomplete_ladder"
    FIRST_SYMPTOM="expected $STAGES stages, recorded ${#ST_OK[@]}"
  fi
  echo "Earliest failing stage: $FIRST_FAIL ($FIRST_FAIL_KIND)"
  echo "First symptom:"
  echo "$FIRST_SYMPTOM"
  echo ""
  echo "Logs under: $OUT_DIR"
  exit 1
fi

echo "Bootstrap ladder: ALL GREEN through stage ${STAGES} (s${STAGES} landmark)."
echo "Logs under: $OUT_DIR"
exit 0
