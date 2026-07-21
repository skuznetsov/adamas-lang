#!/usr/bin/env bash
set -euo pipefail

readonly SCHEMA="t8_fresh_s2_v1"
readonly TIMEOUT_SEC=180
readonly MEM_MB=12288
readonly DEFAULT_LOG_CAP=$((8 * 1024 * 1024))
readonly MAX_LOG_BYTES="${T8_MAX_LOG_BYTES:-$DEFAULT_LOG_CAP}"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source_path=""
out_path=""
host=""
receipt_path=""
keep=0
tmp_dir=""
receipt_ready=0
receipt_written=0
source_hash_before=unknown
source_hash_after=unknown
source_tree_hash_before=unknown
source_tree_hash_after=unknown
git_head=unknown
git_patch_hash_before=unknown
git_patch_hash_after=unknown
runner_hash_before=unknown
runner_hash_after=unknown
validator_hash_before=unknown
validator_hash_after=unknown
cache_mode=unknown
output_fresh=unknown
stage1_hash=unknown
stage2_hash=unknown
stage2_wall_ms=unknown
smoke_plain=unknown
smoke_noprelude=unknown
resource_status=unknown

write_receipt() {
  local status="$1" classification="$2"
  ((receipt_ready == 1 && receipt_written == 0)) || return 0
  local dir tmp
  dir="$(dirname "$receipt_path")"
  if ! mkdir -p "$dir" 2>/dev/null; then
    return 1
  fi
  tmp="$dir/.$(basename "$receipt_path").$$.tmp"
  if ! {
    printf 't8.schema=%s\n' "$SCHEMA"
    printf 't8.status=%s\n' "$status"
    printf 't8.classification=%s\n' "$classification"
    printf 'T8_STATUS=%s\n' "$status"
    printf 'T8_CLASSIFICATION=%s\n' "$classification"
    printf 't8.timeout_sec=%s\n' "$TIMEOUT_SEC"
    printf 't8.mem_mb=%s\n' "$MEM_MB"
    printf 't8.source_sha256_before=%s\n' "$source_hash_before"
    printf 't8.source_sha256_after=%s\n' "$source_hash_after"
    printf 't8.source_tree_sha256_before=%s\n' "$source_tree_hash_before"
    printf 't8.source_tree_sha256_after=%s\n' "$source_tree_hash_after"
    printf 't8.git_head=%s\n' "$git_head"
    printf 't8.git_patch_sha256_before=%s\n' "$git_patch_hash_before"
    printf 't8.git_patch_sha256_after=%s\n' "$git_patch_hash_after"
    printf 't8.runner_sha256_before=%s\n' "$runner_hash_before"
    printf 't8.runner_sha256_after=%s\n' "$runner_hash_after"
    printf 't8.validator_sha256_before=%s\n' "$validator_hash_before"
    printf 't8.validator_sha256_after=%s\n' "$validator_hash_after"
    printf 't8.cache_mode=%s\n' "$cache_mode"
    printf 't8.cache_path_scope=private_tmp\n'
    printf 't8.output_fresh=%s\n' "$output_fresh"
    printf 't8.stage1_sha256=%s\n' "$stage1_hash"
    printf 't8.stage2_sha256=%s\n' "$stage2_hash"
    printf 't8.stage2_wall_ms=%s\n' "$stage2_wall_ms"
    printf 't8.smoke_plain=%s\n' "$smoke_plain"
    printf 't8.smoke_noprelude=%s\n' "$smoke_noprelude"
    printf 't8.resource=%s\n' "$resource_status"
  } >"$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    return 1
  fi
  if ! mv -f "$tmp" "$receipt_path" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    return 1
  fi
  receipt_written=1
}

usage() {
  cat <<'USAGE'
Usage: t8_fresh_s2_readiness_validator.sh --source PATH --out PATH [options]
  --source PATH   source file/tree whose identity is sealed
  --out PATH      new stage output directory
  --host NAME     host label passed to the runner
  --receipt PATH  receipt path (default: --out.t8.receipt)
  --keep          retain private temporary logs
USAGE
}

finish() {
  local status="$1" classification="$2" rc="$3"
  if ! write_receipt "$status" "$classification"; then
    status=ERROR
    classification=receipt_write_failed
    rc=2
  fi
  printf 't8.schema=%s\nT8_STATUS=%s\nT8_CLASSIFICATION=%s\n' "$SCHEMA" "$status" "$classification"
  exit "$rc"
}

fail_arg() {
  printf 't8.schema=%s\nT8_STATUS=ERROR\nT8_CLASSIFICATION=invalid_arguments\n' "$SCHEMA"
  printf 'T8_ERROR=%s\n' "$*" >&2
  exit 2
}

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

hash_path() {
  local path="$1"
  if [[ -f "$path" || -L "$path" ]]; then
    hash_file "$path"
    return
  fi
  if [[ -d "$path" ]]; then
    find "$path" -type f -print0 | sort -z | while IFS= read -r -d '' item; do
      printf '%s  %s\n' "$(hash_file "$item")" "${item#"$path"/}"
    done | hash_stream
    return
  fi
  return 1
}

mode_of() {
  stat -f '%Mp%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || printf 'unknown'
}

hash_tree() {
  local root="$1"
  local rel="${root#"$ROOT_DIR"/}"
  {
    # Git's mode and blob identity cover tracked regular files and symlink
    # targets; git_patch_hash separately seals working-tree content/mode
    # changes. Include untracked entries directly so a new source file cannot
    # disappear from the snapshot.
    git -C "$ROOT_DIR" ls-files -s -co --exclude-standard -- "$rel"
    while IFS= read -r -d '' item; do
      local item_rel mode
      item_rel="${item#"$ROOT_DIR/"}"
      mode="$(mode_of "$item")"
      if [[ -L "$item" ]]; then
        printf 'untracked 120000 %s %s\n' "$(readlink "$item")" "$item_rel"
      else
        printf 'untracked %s %s %s\n' "$mode" "$(hash_file "$item")" "$item_rel"
      fi
    done < <(git -C "$ROOT_DIR" ls-files --others --exclude-standard -z -- "$rel")
  } | LC_ALL=C sort | hash_stream
}

git_head_value() {
  git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown'
}

git_patch_hash() {
  git -C "$ROOT_DIR" diff --binary HEAD -- \
    src scripts/bootstrap_chain.sh scripts/run_safe.sh \
    regression_tests/combined/test_no_prelude_interpolation.cr 2>/dev/null | hash_stream
}

hash_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

field() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | tr ' ' '\n' | sed -n "s/^${key}=//p" | tail -1
}

log_size() {
  wc -c <"$1" | tr -d '[:space:]'
}

physical_path() {
  realpath "$1" 2>/dev/null || return 1
}

dev_inode() {
  stat -f '%d:%i' "$1" 2>/dev/null || stat -c '%d:%i' "$1" 2>/dev/null || return 1
}

link_count() {
  stat -f '%l' "$1" 2>/dev/null || stat -c '%h' "$1" 2>/dev/null || return 1
}

log_entry_ok() {
  local path="$1" root_real="$2" path_real count
  [[ -f "$path" && ! -L "$path" ]] || return 1
  count="$(link_count "$path")" || return 1
  [[ "$count" == 1 ]] || return 1
  path_real="$(physical_path "$path")" || return 1
  case "$path_real" in
    "$root_real"/*) return 0 ;;
    *) return 1 ;;
  esac
}

log_cap_exceeded() {
  local root="$1" total=0 item
  if [[ -d "$root" ]]; then
    while IFS= read -r -d '' item; do
      total=$((total + $(log_size "$item")))
      ((total > MAX_LOG_BYTES)) && return 0
    done < <(find "$root" -type f -name '*.log' -print0)
  fi
  return 1
}

capture_partial_evidence() {
  if [[ -f "$out_path/cv2_s1" && ! -L "$out_path/cv2_s1" ]]; then
    stage1_hash="$(hash_file "$out_path/cv2_s1" 2>/dev/null || printf 'unknown')"
  fi
  if [[ -f "$out_path/stage2_build.log" && ! -L "$out_path/stage2_build.log" ]]; then
    local partial_real
    partial_real="$(grep '^real ' "$out_path/stage2_build.log" | tail -1 || true)"
    if [[ "$partial_real" =~ ^real[[:space:]]+([0-9]+)\.([0-9]+)$ ]]; then
      local whole="${BASH_REMATCH[1]}" fraction="${BASH_REMATCH[2]}"
      while ((${#fraction} < 3)); do fraction="${fraction}0"; done
      stage2_wall_ms=$((10#$whole * 1000 + 10#${fraction:0:3}))
    fi
  fi
}

while (($#)); do
  case "$1" in
    --source) (($# >= 2)) || fail_arg "--source requires a value"; source_path="$2"; shift 2 ;;
    --out) (($# >= 2)) || fail_arg "--out requires a value"; out_path="$2"; shift 2 ;;
    --host) (($# >= 2)) || fail_arg "--host requires a value"; host="$2"; shift 2 ;;
    --receipt) (($# >= 2)) || fail_arg "--receipt requires a value"; receipt_path="$2"; shift 2 ;;
    --keep) keep=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail_arg "unknown argument: $1" ;;
  esac
done

[[ -n "$source_path" && -n "$out_path" ]] || fail_arg "--source and --out are required"
[[ -e "$source_path" || -L "$source_path" ]] || fail_arg "source does not exist"
[[ "$MAX_LOG_BYTES" =~ ^[1-9][0-9]*$ ]] || fail_arg "invalid log cap"
receipt_path="${receipt_path:-${out_path}.t8.receipt}"

runner="${T8_BOOTSTRAP_RUNNER:-${T8_CHAIN_RUNNER:-$ROOT_DIR/scripts/bootstrap_chain.sh}}"
runner_file="$(command -v "$runner" 2>/dev/null || true)"
validator_file="$0"
source_hash_before="$(hash_path "$source_path" 2>/dev/null || true)"
source_tree_hash_before="$(hash_tree "$ROOT_DIR/src" 2>/dev/null || true)"
git_head="$(git_head_value)"
git_patch_hash_before="$(git_patch_hash)"
runner_hash_before="$(hash_path "$runner_file" 2>/dev/null || true)"
validator_hash_before="$(hash_path "$validator_file" 2>/dev/null || true)"
receipt_ready=1

if [[ -L "$out_path" ]]; then output_fresh=0; finish ERROR output_symlink 2; fi
if [[ -e "$out_path" ]]; then output_fresh=0; finish ERROR output_reused 2; fi
if [[ -e "$receipt_path" || -L "$receipt_path" ]]; then receipt_ready=0; finish ERROR receipt_reused 2; fi
[[ -n "$source_hash_before" && -n "$validator_hash_before" ]] || finish ERROR source_hash_mismatch 2
output_fresh=1

if ! mkdir "$out_path" 2>/dev/null; then finish ERROR internal_error 2; fi
output_real_before="$(physical_path "$out_path" 2>/dev/null || true)"
output_id_before="$(dev_inode "$out_path" 2>/dev/null || true)"
if [[ -z "$output_real_before" || -z "$output_id_before" ]]; then finish ERROR internal_error 2; fi

if ! tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/t8_fresh_s2.XXXXXX" 2>/dev/null)"; then finish ERROR internal_error 2; fi
cleanup() {
  if ((keep == 0)); then rm -rf "$tmp_dir"; else printf 'T8_TMP_DIR=%s\n' "$tmp_dir" >&2; fi
}
trap cleanup EXIT
runner_log="$tmp_dir/runner.log"

err_in_progress=0
on_internal_error() {
  local err_rc=$?
  if ((err_in_progress)); then exit "$err_rc"; fi
  err_in_progress=1
  finish ERROR internal_error 2
}
trap on_internal_error ERR

runner_args=(--source "$source_path" --out "$out_path" --stages 2 --timeout "$TIMEOUT_SEC" --mem "$MEM_MB")
[[ -n "$host" ]] && runner_args+=(--host "$host")
if ! mkdir -p "$tmp_dir/crystal_cache"; then finish ERROR internal_error 2; fi
cache_mode=cold
runner_pid=""
runner_pgid=""
watchdog_pid=""
watchdog_status="$tmp_dir/watchdog.status"
kill_runner_group() {
  [[ -n "$runner_pid" ]] || return 0
  [[ -n "$runner_pgid" ]] || runner_pgid="$runner_pid"
  # With job control enabled, the background runner owns a fresh process
  # group whose id is the runner pid.  Signal the whole group so nested
  # bootstrap/run_safe children cannot outlive the watchdog.
  kill -TERM -- "-$runner_pgid" 2>/dev/null || true
  # Give TERM handlers enough time to remove their sentinels and reap nested
  # children.  Avoid ps/pgrep here: sandboxed hosts may deny process queries.
  local i
  for i in $(seq 1 35); do
    kill -0 -- "-$runner_pgid" 2>/dev/null || return 0
    sleep 0.1 || true
  done
  kill -KILL -- "-$runner_pgid" 2>/dev/null || true
}
watchdog_loop() {
  # The parent owns/reaps the runner.  This child only enforces the cap and
  # exits when the runner disappears; polling kill -0 from the parent would
  # keep observing an unreaped zombie on macOS.
  trap - ERR HUP INT TERM
  set +e
  while :; do
    if log_cap_exceeded "$out_path" || { [[ -f "$runner_log" ]] && (( $(log_size "$runner_log") > MAX_LOG_BYTES )); }; then
      printf 'output_cap_exceeded\n' >"$watchdog_status"
      kill_runner_group
      return 0
    fi
    if ! kill -0 "$runner_pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.2 || true
  done
}
on_interrupt() {
  kill_runner_group
  if [[ -n "$watchdog_pid" ]]; then
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  wait "$runner_pid" 2>/dev/null || true
  capture_partial_evidence
  finish ERROR interrupted 2
}
trap on_interrupt HUP INT TERM
trap - ERR
set -m
set +e
CRYSTAL_CACHE_DIR="$tmp_dir/crystal_cache" "$runner" "${runner_args[@]}" >"$runner_log" 2>&1 &
runner_pid=$!
# `set -m` above gives this background job its own process group.  The pid is
# therefore the pgid; do not query ps, which is unavailable in some sandboxes.
runner_pgid="$runner_pid"
set -e
watchdog_loop &
watchdog_pid=$!
set +e
wait "$runner_pid"
runner_rc=$?
wait "$watchdog_pid" 2>/dev/null || true
set -e
set +m
trap - HUP INT TERM
trap on_internal_error ERR

if [[ -s "$watchdog_status" ]] && [[ "$(<"$watchdog_status")" == output_cap_exceeded ]]; then
  capture_partial_evidence
  finish ERROR output_cap_exceeded 2
fi

source_hash_after="$(hash_path "$source_path" 2>/dev/null || true)"
source_tree_hash_after="$(hash_tree "$ROOT_DIR/src" 2>/dev/null || true)"
git_patch_hash_after="$(git_patch_hash)"
git_head_after="$(git_head_value)"
if [[ "$source_hash_before" != "$source_hash_after" || "$source_tree_hash_before" != "$source_tree_hash_after" || "$git_patch_hash_before" != "$git_patch_hash_after" || "$git_head" != "$git_head_after" ]]; then
  finish ERROR source_hash_mismatch 2
fi
runner_hash_after="$(hash_path "$runner_file" 2>/dev/null || true)"
validator_hash_after="$(hash_path "$validator_file" 2>/dev/null || true)"
if [[ -n "$runner_hash_before" && "$runner_hash_before" != "$runner_hash_after" ]]; then finish ERROR runner_hash_mismatch 2; fi
if [[ "$validator_hash_before" != "$validator_hash_after" ]]; then finish ERROR validator_hash_mismatch 2; fi

output_real_after="$(physical_path "$out_path" 2>/dev/null || true)"
output_id_after="$(dev_inode "$out_path" 2>/dev/null || true)"
if [[ ! -d "$out_path" || -L "$out_path" || -z "$output_real_after" || -z "$output_id_after" ||
      "$output_real_before" != "$output_real_after" || "$output_id_before" != "$output_id_after" ]]; then
  finish ERROR output_namespace_changed 2
fi
symlink_item="$(find "$out_path" -type l -print -quit 2>/dev/null || true)"
if [[ -n "$symlink_item" ]]; then
  case "$symlink_item" in
    "$out_path/cv2_s1") finish ERROR stage1_artifact_symlink 2 ;;
    "$out_path/cv2_s2") finish ERROR stage2_artifact_symlink 2 ;;
    *) finish ERROR output_symlink 2 ;;
  esac
fi

if [[ -d "$out_path" ]]; then
  total_bytes=0
  while IFS= read -r -d '' item; do
    total_bytes=$((total_bytes + $(log_size "$item")))
    (( total_bytes <= MAX_LOG_BYTES )) || finish ERROR output_cap_exceeded 2
  done < <(find "$out_path" -type f -name '*.log' -print0)
fi
(( $(log_size "$runner_log") <= MAX_LOG_BYTES )) || finish ERROR output_cap_exceeded 2

s2_log="$out_path/stage2_build.log"
if [[ -e "$s2_log" ]] && ! log_entry_ok "$s2_log" "$output_real_before"; then finish ERROR output_symlink 2; fi
if [[ -f "$s2_log" ]]; then
  if grep -q '\[KILL\].*[Tt]imeout' "$s2_log"; then capture_partial_evidence; finish MEASURED_RED stage2_timeout 1; fi
  if [[ "$runner_rc" == 1 || "$runner_rc" == 143 ]] && grep -q '\[EXIT: 143\]' "$s2_log"; then finish ERROR ambiguous_exit_143 2; fi
fi
if ((runner_rc != 0)); then finish ERROR runner_error 2; fi

if [[ -L "$out_path/cv2_s1" ]]; then finish ERROR stage1_artifact_symlink 2; fi
if [[ ! -e "$out_path/cv2_s1" || ! -f "$out_path/cv2_s1" || ! -x "$out_path/cv2_s1" ]]; then
  finish ERROR stage1_artifact_missing 2
fi
if [[ -L "$out_path/cv2_s2" ]]; then finish ERROR stage2_artifact_symlink 2; fi
if [[ ! -e "$out_path/cv2_s2" || ! -f "$out_path/cv2_s2" || ! -x "$out_path/cv2_s2" ]]; then
  finish ERROR stage2_artifact_missing 2
fi

stage1_hash="$(hash_file "$out_path/cv2_s1")"
stage2_hash="$(hash_file "$out_path/cv2_s2")"
prov_line="$(grep '^\[PROVENANCE\].*stage1_sha256=' "$s2_log" | tail -1 || true)"
prov_stage1="$(field "$prov_line" stage1_sha256)"
prov_stage2="$(field "$prov_line" stage2_sha256)"
prov_parent="$(field "$prov_line" parent_sha256)"
provenance_mismatch=0
if [[ -n "$prov_line" && ( "$prov_stage1" != "$stage1_hash" || "$prov_stage2" != "$stage2_hash" || "$prov_parent" != "$stage1_hash" ) ]]; then
  provenance_mismatch=1
fi
lineage_line="$(grep '^\[LINEAGE\]' "$s2_log" | tail -1 || true)"
if [[ -n "$lineage_line" && "$(field "$lineage_line" stage2_parent_sha256)" != "$stage1_hash" ]]; then provenance_mismatch=1; fi

cache_line="$(grep '^\[CACHE\]' "$s2_log" | tail -1 || true)"
cache_mode="cold"
cache_nonfresh=0
cache_mismatch=0
if [[ -n "$cache_line" ]]; then
  cache_mode="$(field "$cache_line" cache_mode)"
  cache_identity="$(field "$cache_line" cache_identity)"
  if [[ "$cache_mode" == warm ]]; then cache_nonfresh=1; fi
  if [[ "$cache_mode" == cold && "$cache_identity" != "" ]]; then cache_mismatch=1; fi
fi

resource_count="$(grep -c '^\[RESOURCE\]' "$s2_log" 2>/dev/null || true)"
resource_line="$(grep '^\[RESOURCE\]' "$s2_log" 2>/dev/null || true)"
resource_status="unknown"
required_resource=(schema outcome reason exit_code max_rss_kb max_fd rss_samples fd_samples rss_available fd_available process_tree_mode tree_coverage tree_samples tree_complete_samples tree_incomplete_samples max_tree_pids)
missing_resource=0
resource_malformed=0
if [[ "$resource_count" -gt 1 ]] 2>/dev/null; then
  resource_malformed=1
elif [[ -n "$resource_line" ]]; then
  for key in "${required_resource[@]}"; do
    [[ -n "$(field "$resource_line" "$key")" ]] || missing_resource=1
  done
  if ((missing_resource == 0)); then
    [[ "$(field "$resource_line" schema)" == t8_resource_v1 && "$(field "$resource_line" outcome)" == success && "$(field "$resource_line" reason)" == completed ]] || resource_malformed=1
    for key in exit_code max_rss_kb max_fd rss_samples fd_samples tree_samples tree_complete_samples tree_incomplete_samples max_tree_pids; do
      [[ "$(field "$resource_line" "$key")" =~ ^[0-9]+$ ]] || resource_malformed=1
    done
    [[ "$(field "$resource_line" rss_available)" =~ ^(yes|no)$ && "$(field "$resource_line" fd_available)" =~ ^(yes|no)$ ]] || resource_malformed=1
    [[ "$(field "$resource_line" process_tree_mode)" =~ ^(pgid|recursive|process_tree)$ && "$(field "$resource_line" tree_coverage)" == complete ]] || resource_malformed=1
    resource_status=complete
    if [[ "$(field "$resource_line" exit_code)" != 0 ||
          "$(field "$resource_line" max_rss_kb)" -le 0 ||
          "$(field "$resource_line" max_fd)" -le 0 ||
          "$(field "$resource_line" rss_available)" != yes ||
          "$(field "$resource_line" fd_available)" != yes ||
          "$(field "$resource_line" tree_coverage)" != complete ||
          "$(field "$resource_line" tree_incomplete_samples)" != 0 ||
          "$(field "$resource_line" tree_complete_samples)" != "$(field "$resource_line" tree_samples)" ]]; then
      resource_malformed=1
    fi
    for key in rss_samples fd_samples tree_samples tree_complete_samples max_tree_pids; do
      [[ "$(field "$resource_line" "$key")" -gt 0 ]] 2>/dev/null || resource_malformed=1
    done
  fi
fi

real_line="$(grep '^real ' "$s2_log" | tail -1 || true)"
wall_malformed=0
stage2_wall_ms=0
if [[ "$real_line" =~ ^real[[:space:]]+([0-9]+)\.([0-9]+)$ ]]; then
  whole="${BASH_REMATCH[1]}"; fraction="${BASH_REMATCH[2]}"
  while ((${#fraction} < 3)); do fraction="${fraction}0"; done
  fraction="${fraction:0:3}"
  stage2_wall_ms=$((10#$whole * 1000 + 10#$fraction))
else
  wall_malformed=1
fi

expected_plain="$tmp_dir/plain.expected"
expected_noprelude="$tmp_dir/noprelude.expected"
printf '=== STDOUT ===\n42\n=== STDERR ===\n[EXIT: 0] after ~0s\n' >"$expected_plain"
printf '=== STDOUT ===\nhello world\nn=42\nnoprelude_interp_ok\n=== STDERR ===\n[EXIT: 0] after ~0s\n' >"$expected_noprelude"

plain_runtime="$out_path/_smoke_puts42.runtime.log"
noprelude_runtime="$out_path/_smoke_noprel.runtime.log"
if [[ -e "$plain_runtime" ]] && ! log_entry_ok "$plain_runtime" "$output_real_before"; then finish ERROR output_symlink 2; fi
if [[ -e "$noprelude_runtime" ]] && ! log_entry_ok "$noprelude_runtime" "$output_real_before"; then finish ERROR output_symlink 2; fi
if [[ ! -f "$plain_runtime" ]]; then smoke_plain=unavailable; finish MEASURED_RED plain_smoke_unavailable 1; fi
if [[ ! -f "$noprelude_runtime" ]]; then smoke_noprelude=unavailable; finish MEASURED_RED noprelude_smoke_unavailable 1; fi
smoke_matches() {
  local path="$1" kind="$2"
  awk -v kind="$kind" '
    $0 == "=== STDOUT ===" {
      if (stdout_count > 0 || stderr_count > 0) bad = 1
      stdout_count++; mode = 1; next
    }
    $0 == "=== STDERR ===" {
      if (stdout_count != 1 || stderr_count > 0 || mode != 1) bad = 1
      stderr_count++; mode = 2; next
    }
    mode == 1 { if (stdout != "") stdout = stdout "\n"; stdout = stdout $0; next }
    mode == 2 {
      if ($0 ~ /^\[EXIT: 0\] after ~[0-9]+s$/) {
        if (diagnostic) bad = 1
        diagnostic = 1
      } else if ($0 != "" || diagnostic) { bad = 1 }
      next
    }
    { bad = 1 }
    END {
      expected = kind == "plain" ? "42" : "hello world\nn=42\nnoprelude_interp_ok"
      exit !(stdout_count == 1 && stderr_count == 1 && stdout == expected && diagnostic && !bad)
    }
  ' "$path"
}
if ! smoke_matches "$plain_runtime" plain || ! smoke_matches "$noprelude_runtime" noprelude; then
  smoke_plain=fail
  smoke_noprelude=fail
  finish MEASURED_RED smoke_output_mismatch 1
fi

if [[ "$stage2_wall_ms" =~ ^[0-9]+$ ]] && ((stage2_wall_ms > TIMEOUT_SEC * 1000)); then finish MEASURED_RED over_budget 1; fi
if ((wall_malformed)); then finish ERROR malformed_resource 2; fi
if ((cache_nonfresh)); then finish MEASURED_RED warm_cache_nonfresh 1; fi
if ((cache_mismatch)); then finish ERROR cache_identity_mismatch 2; fi
if ((provenance_mismatch)); then finish ERROR provenance_mismatch 2; fi
if [[ -z "$resource_line" || $missing_resource -ne 0 ]]; then finish RESOURCE_UNKNOWN resource_unknown 1; fi
if ((resource_malformed)); then finish ERROR malformed_resource 2; fi
smoke_plain=pass
smoke_noprelude=pass
finish GREEN fresh_both_smoke 0
