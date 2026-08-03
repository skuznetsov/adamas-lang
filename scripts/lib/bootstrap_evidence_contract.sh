#!/usr/bin/env bash
# Shared bootstrap_chain_v3 and run_safe_resource_v1 parsing contracts.

BOOTSTRAP_SUCCESS_RESOURCE_ROW_RE='^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=0 max_rss_kb=([0-9]+|unknown) max_fd=([0-9]+|unknown) rss_samples=[0-9]+ fd_samples=[0-9]+ rss_available=(yes|unknown) fd_available=(yes|unknown) process_tree_mode=(ps_ancestry_snapshot|unknown) tree_coverage=(all_scheduled_snapshots|unknown) fd_tree_coverage=(all_stable_pairs|unknown) tree_samples=[0-9]+ fd_topology_stable_samples=[0-9]+ fd_topology_unstable_samples=[0-9]+ max_tree_pids=[0-9]+$'
BOOTSTRAP_EXIT_ZERO_ROW_RE='^\[EXIT: 0\] after ~[0-9]+s$'

bootstrap_file_nlink() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f '%l' "$1" 2>/dev/null
  else
    stat -c '%h' -- "$1" 2>/dev/null
  fi
}

bootstrap_directory_identity() {
  [[ -d "$1" && ! -L "$1" ]] || return 1
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f '%d:%i' "$1" 2>/dev/null
  else
    stat -c '%d:%i' -- "$1" 2>/dev/null
  fi
}

bootstrap_directory_mode() {
  [[ -d "$1" && ! -L "$1" ]] || return 1
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f '%Lp' "$1" 2>/dev/null
  else
    stat -c '%a' -- "$1" 2>/dev/null
  fi
}

bootstrap_resource_field() {
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

bootstrap_resource_schema() {
  bootstrap_resource_field schema "$1"
}

bootstrap_exact_success_resource_row() {
  [[ "$1" =~ $BOOTSTRAP_SUCCESS_RESOURCE_ROW_RE ]]
}

bootstrap_exact_success_resource_file() {
  local resource_file="$1"
  local line
  local -a lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines[${#lines[@]}]="$line"
  done < "$resource_file"
  [[ "${#lines[@]}" -eq 1 ]] && bootstrap_exact_success_resource_row "${lines[0]}"
}

bootstrap_build_resource_row() {
  local build_log="$1"
  awk '
    /^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 / { rows++; value = $0 }
    END { if (rows == 1) print value }
  ' "$build_log"
}

bootstrap_build_wall() {
  local build_log="$1"
  awk '
    /^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 / {
      resource_count++
      after_owned_resource = 1
      resource_line = NR
      next
    }
    after_owned_resource && $0 ~ /^real [0-9]+([.][0-9][0-9]?)?$/ {
      real_count++
      value = $2
      real_line = NR
      next
    }
    after_owned_resource && $0 ~ /^user [0-9]+([.][0-9][0-9]?)?$/ {
      user_count++
      user_line = NR
      next
    }
    after_owned_resource && $0 ~ /^sys [0-9]+([.][0-9][0-9]?)?$/ {
      sys_count++
      sys_line = NR
      next
    }
    END {
      if (resource_count == 1 && real_count == 1 && user_count == 1 && sys_count == 1 &&
          real_line == resource_line + 1 && user_line == real_line + 1 &&
          sys_line == user_line + 1 && sys_line == NR) print value
    }
  ' "$build_log"
}

bootstrap_exact_smoke_transcript() {
  local runtime_log="$1"
  local marker="$2"
  local line
  local -a lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines[${#lines[@]}]="$line"
  done < "$runtime_log"
  case "$marker" in
    42)
      [[ "${#lines[@]}" -eq 5 ]] &&
        [[ "${lines[0]}" == "=== STDOUT ===" ]] &&
        [[ "${lines[1]}" == "42" ]] &&
        [[ "${lines[2]}" == "=== STDERR ===" ]] &&
        [[ "${lines[3]}" =~ $BOOTSTRAP_EXIT_ZERO_ROW_RE ]] &&
        bootstrap_exact_success_resource_row "${lines[4]}"
      ;;
    noprelude_interp_ok)
      [[ "${#lines[@]}" -eq 7 ]] &&
        [[ "${lines[0]}" == "=== STDOUT ===" ]] &&
        [[ "${lines[1]}" == "hello world" ]] &&
        [[ "${lines[2]}" == "n=42" ]] &&
        [[ "${lines[3]}" == "noprelude_interp_ok" ]] &&
        [[ "${lines[4]}" == "=== STDERR ===" ]] &&
        [[ "${lines[5]}" =~ $BOOTSTRAP_EXIT_ZERO_ROW_RE ]] &&
        bootstrap_exact_success_resource_row "${lines[6]}"
      ;;
    *)
      return 1
      ;;
  esac
}
