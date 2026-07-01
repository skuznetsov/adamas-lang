#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler> [source.cr [compiler-args...]]" >&2
  echo "env: TIMEOUT=180 MEM_MB=4096 SAMPLES=8" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
shift

TIMEOUT="${TIMEOUT:-180}"
MEM_MB="${MEM_MB:-4096}"
SAMPLES="${SAMPLES:-8}"
mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/codepath-status-runtime.XXXXXX")"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ $# -eq 0 ]]; then
  SRC="$TMP_DIR/repro.cr"
  OUT="$TMP_DIR/repro"
  cat >"$SRC" <<'CR'
x = 1
CR
  COMPILE_ARGS=("$SRC" --no-prelude -o "$OUT")
else
  SRC="$1"
  shift
  COMPILE_ARGS=("$SRC" "$@")
fi

set +e
ADAMAS_CODEPATH_STATUS_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${COMPILE_ARGS[@]}" >"$LOG" 2>&1
compiler_rc=$?
set -e

if ! grep -q '^\[CODEPATH_STATUS\]' "$LOG"; then
  echo "FAIL: no [CODEPATH_STATUS] runtime rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -100 "$LOG" >&2 || true
  exit 1
fi

echo "# CodePathStatus Runtime Report"
echo "compiler: $COMPILER"
echo "source: $SRC"
echo "compiler_rc: $compiler_rc"
echo "samples_per_section: $SAMPLES"
echo "note: report is diagnostic; rows are runtime evidence, not delete-ready proof"

awk -v samples="$SAMPLES" '
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
    row_count++
    category = field("category")
    path = field("path")
    status = field("status")
    owner = field("owner")
    note = field("note")
    last_row = $0

    category_count[category]++
    status_count[status]++
    path_count[path]++

    if (category == "" || path == "" || status == "" || owner == "") {
      malformed++
      if (sample_count["malformed"] < samples) {
        sample_count["malformed"]++
        sample["malformed", sample_count["malformed"]] = $0
      }
    }

    if (sample_count[status] < samples) {
      sample_count[status]++
      sample[status, sample_count[status]] = "category=" category " path=" path " owner=" owner " note=" note
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" row_count + 0
    print "malformed=" malformed + 0

    print ""
    print "## Statuses"
    for (s in status_count) {
      print s "=" status_count[s]
    }

    print ""
    print "## Categories"
    for (c in category_count) {
      print c "=" category_count[c]
    }

    print ""
    print "## Paths"
    for (p in path_count) {
      print p "=" path_count[p]
    }

    print ""
    print "## Samples By Status"
    for (s in status_count) {
      print "### " s
      for (i = 1; i <= sample_count[s]; i++) {
        print sample[s, i]
      }
    }

    print ""
    print "## Malformed Samples"
    if ((sample_count["malformed"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["malformed"]; i++) {
        print sample["malformed", i]
      }
    }

    print ""
    print "## Last Row"
    print last_row

    if ((row_count + 0) == 0 || (malformed + 0) != 0) {
      exit 1
    }
  }
' "$LOG"

if [[ $compiler_rc -ne 0 ]]; then
  echo ""
  echo "## Nonzero Compiler Tail"
  tail -80 "$LOG" || true
fi
