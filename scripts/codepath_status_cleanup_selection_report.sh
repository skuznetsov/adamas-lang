#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler> [source.cr [compiler-args...]]" >&2
  echo "env: TIMEOUT=180 MEM_MB=4096 SELECTED_CLEANUP_PATH=identity_dry_run LIST_RUNTIME_PATHS=0 REQUIRE_DELETE_READY=0" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
shift

TIMEOUT="${TIMEOUT:-180}"
MEM_MB="${MEM_MB:-4096}"
SELECTED_CLEANUP_PATH="${SELECTED_CLEANUP_PATH:-identity_dry_run}"
LIST_RUNTIME_PATHS="${LIST_RUNTIME_PATHS:-0}"
REQUIRE_DELETE_READY="${REQUIRE_DELETE_READY:-0}"
mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/codepath-status-cleanup.XXXXXX")"
DEFAULT_LOG="$TMP_DIR/default.log"
ENABLED_LOG="$TMP_DIR/enabled.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ $# -eq 0 ]]; then
  SRC="$TMP_DIR/repro.cr"
  OUT_DEFAULT="$TMP_DIR/default.bin"
  OUT_ENABLED="$TMP_DIR/enabled.bin"
  cat >"$SRC" <<'CR'
x = 1
CR
  DEFAULT_ARGS=("$SRC" --no-prelude -o "$OUT_DEFAULT")
  ENABLED_ARGS=("$SRC" --no-prelude -o "$OUT_ENABLED")
else
  SRC="$1"
  shift
  OUT_DEFAULT="$TMP_DIR/default.bin"
  OUT_ENABLED="$TMP_DIR/enabled.bin"
  DEFAULT_ARGS=("$SRC" "$@" -o "$OUT_DEFAULT")
  ENABLED_ARGS=("$SRC" "$@" -o "$OUT_ENABLED")
fi

selected_env_name() {
  case "$SELECTED_CLEANUP_PATH" in
    identity_dry_run)
      echo "ADAMAS_IDENTITY_DRY_RUN"
      ;;
    phase0_metrics)
      echo "ADAMAS_PHASE0_METRICS"
      ;;
    *)
      echo "unsupported SELECTED_CLEANUP_PATH=$SELECTED_CLEANUP_PATH" >&2
      exit 2
      ;;
  esac
}

SELECTED_ENV="$(selected_env_name)"

set +e
ADAMAS_CODEPATH_STATUS_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${DEFAULT_ARGS[@]}" >"$DEFAULT_LOG" 2>&1
default_rc=$?

env ADAMAS_CODEPATH_STATUS_LEDGER=1 "$SELECTED_ENV=1" \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${ENABLED_ARGS[@]}" >"$ENABLED_LOG" 2>&1
enabled_rc=$?
set -e

extract_status() {
  local log="$1"
  awk -v wanted="$SELECTED_CLEANUP_PATH" '
    function field(name,    i, p) {
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p > 0 && substr($i, 1, p - 1) == name) {
          return substr($i, p + 1)
        }
      }
      return ""
    }

    /^\[CODEPATH_STATUS\]/ {
      rows++
      path = field("path")
      status = field("status")
      category = field("category")
      owner = field("owner")
      if (path == wanted) {
        selected_rows++
        selected_status = status
        selected_category = category
        selected_owner = owner
      }
      if (category == "" || path == "" || status == "" || owner == "") {
        malformed++
      }
    }

    END {
      print "rows=" rows + 0
      print "malformed=" malformed + 0
      print "selected_rows=" selected_rows + 0
      print "selected_status=" selected_status
      print "selected_category=" selected_category
      print "selected_owner=" selected_owner
    }
  ' "$log"
}

runtime_inventory() {
  local log="$1"
  awk '
    function field(name,    i, p) {
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p > 0 && substr($i, 1, p - 1) == name) {
          return substr($i, p + 1)
        }
      }
      return ""
    }

    /^\[CODEPATH_STATUS\]/ {
      rows++
      category = field("category")
      path = field("path")
      status = field("status")
      owner = field("owner")

      if (path == "") {
        malformed++
        next
      }

      if (!(path in seen)) {
        seen[path] = 1
        order[++path_total] = path
        path_category[path] = category
        path_owner[path] = owner
      }

      path_rows[path]++
      if (status == "taken") {
        path_taken[path]++
      } else if (status == "not_taken") {
        path_not_taken[path]++
      } else {
        path_other[path]++
      }
    }

    END {
      print "inventory_rows=" rows + 0
      print "inventory_paths=" path_total + 0
      print "inventory_malformed=" malformed + 0
      print "inventory_delete_ready_rows=0"
      print "inventory_status=no_delete_ready_candidate"
      for (i = 1; i <= path_total; i++) {
        path = order[i]
        if ((path_taken[path] + 0) > 0) {
          klass = "live_default"
        } else if ((path_not_taken[path] + 0) > 0) {
          klass = "not_taken_unproven"
        } else {
          klass = "unknown_status"
        }
        print "inventory_path=" path " category=" path_category[path] " owner=" path_owner[path] " default_taken=" (path_taken[path] + 0) " default_not_taken=" (path_not_taken[path] + 0) " default_other=" (path_other[path] + 0) " cleanup_class=" klass
      }
    }
  ' "$log"
}

default_summary="$(extract_status "$DEFAULT_LOG")"
enabled_summary="$(extract_status "$ENABLED_LOG")"

field_from_summary() {
  local summary="$1"
  local key="$2"
  printf '%s\n' "$summary" | awk -F= -v key="$key" '$1 == key { print $2; found = 1 } END { if (!found) print "" }'
}

default_rows="$(field_from_summary "$default_summary" rows)"
default_malformed="$(field_from_summary "$default_summary" malformed)"
default_selected_rows="$(field_from_summary "$default_summary" selected_rows)"
default_status="$(field_from_summary "$default_summary" selected_status)"
default_category="$(field_from_summary "$default_summary" selected_category)"
default_owner="$(field_from_summary "$default_summary" selected_owner)"

enabled_rows="$(field_from_summary "$enabled_summary" rows)"
enabled_malformed="$(field_from_summary "$enabled_summary" malformed)"
enabled_selected_rows="$(field_from_summary "$enabled_summary" selected_rows)"
enabled_status="$(field_from_summary "$enabled_summary" selected_status)"
enabled_category="$(field_from_summary "$enabled_summary" selected_category)"
enabled_owner="$(field_from_summary "$enabled_summary" selected_owner)"
inventory_summary=""
inventory_status=""
if [[ "$LIST_RUNTIME_PATHS" == "1" || "$REQUIRE_DELETE_READY" == "1" ]]; then
  inventory_summary="$(runtime_inventory "$DEFAULT_LOG")"
  inventory_status="$(field_from_summary "$inventory_summary" inventory_status)"
fi

echo "# CodePathStatus Cleanup Selection Report"
echo "compiler: $COMPILER"
echo "source: $SRC"
echo "selected_path: $SELECTED_CLEANUP_PATH"
echo "selected_env: $SELECTED_ENV"
echo "list_runtime_paths: $LIST_RUNTIME_PATHS"
echo "require_delete_ready: $REQUIRE_DELETE_READY"
echo "default_rc: $default_rc"
echo "enabled_rc: $enabled_rc"
echo "note: selection only; no path is delete_ready from this report"
echo ""
echo "## Default Run"
echo "$default_summary"
echo ""
echo "## Enabled Run"
echo "$enabled_summary"
echo ""
echo "## Selection"
echo "[CODEPATH_CLEANUP_SELECTION] cluster=cli.metrics path=$SELECTED_CLEANUP_PATH owner=CLI status=debug_only default_status=$default_status enabled_status=$enabled_status default_rows=$default_selected_rows enabled_rows=$enabled_selected_rows protecting_falsifier=env_off_not_taken_env_on_taken action=classify_only"

if [[ -n "$inventory_summary" ]]; then
  echo ""
  echo "## Runtime Path Inventory"
  echo "$inventory_summary"
fi

if [[ "$default_rc" -ne 0 || "$enabled_rc" -ne 0 ]]; then
  echo "FAIL: compiler run failed" >&2
  exit 1
fi

if [[ "$default_rows" == "0" || "$enabled_rows" == "0" ||
      "$default_malformed" != "0" || "$enabled_malformed" != "0" ]]; then
  echo "FAIL: malformed or missing CODEPATH_STATUS rows" >&2
  exit 1
fi

if [[ "$default_selected_rows" != "1" || "$enabled_selected_rows" != "1" ||
      "$default_status" != "not_taken" || "$enabled_status" != "taken" ||
      "$default_category" != "cli.metrics" || "$enabled_category" != "cli.metrics" ||
      "$default_owner" != "CLI" || "$enabled_owner" != "CLI" ]]; then
  echo "FAIL: selected cleanup path did not match debug-only shape" >&2
  exit 1
fi

if [[ "$REQUIRE_DELETE_READY" == "1" &&
      "$inventory_status" != "eligible_delete_ready_candidate" ]]; then
  echo "FAIL: inventory_status=$inventory_status expected=eligible_delete_ready_candidate" >&2
  exit 9
fi
