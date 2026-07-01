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
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/semantic-state-scope.XXXXXX")"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ $# -eq 0 ]]; then
  SRC="$TMP_DIR/repro.cr"
  OUT="$TMP_DIR/repro.bin"
  cat >"$SRC" <<'CR'
class Box
  def initialize(@x : Int32)
  end

  def value
    @x
  end
end

box = Box.new(7)
puts box.value
CR
  COMPILE_ARGS=("$SRC" -o "$OUT")
else
  SRC="$1"
  shift
  COMPILE_ARGS=("$SRC" "$@")
fi

set +e
ADAMAS_SEMANTIC_STATE_SCOPE_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${COMPILE_ARGS[@]}" >"$LOG" 2>&1
compiler_rc=$?
set -e

if ! grep -q '^\[STATE_SCOPE\]' "$LOG"; then
  echo "FAIL: no [STATE_SCOPE] semantic state-scope rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -100 "$LOG" >&2 || true
  exit 1
fi

echo "# Semantic StateScope Report"
echo "compiler: $COMPILER"
echo "source: $SRC"
echo "compiler_rc: $compiler_rc"
echo "samples_per_section: $SAMPLES"
echo "note: report is diagnostic; nonzero compiler_rc is allowed when rows exist"

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

  /^\[STATE_SCOPE\]/ {
    rows++
    tx = field("tx")
    authority = field("authority")
    map_source = field("map_source")
    allowed = field("allowed_consumers")
    forbidden = field("forbidden_consumers")
    lifetime = field("lifetime_region")
    validation = field("validation")
    requested = field("requested")
    target = field("target")
    ambient = field("ambient_map")
    target_map = field("target_map")
    last_row = $0

    authority_count[authority]++
    map_source_count[map_source]++
    validation_count[validation]++
    lifetime_count[lifetime]++

    if (tx == "" || authority == "" || map_source == "" || allowed == "" ||
        forbidden == "" || lifetime == "" || validation == "" ||
        requested == "" || target == "") {
      malformed++
      if (sample_count["malformed"] < samples) {
        sample_count["malformed"]++
        sample["malformed", sample_count["malformed"]] = $0
      }
    }

    if (validation != "owned" && validation != "ambient_rejected") {
      invalid_validation++
      if (sample_count["invalid_validation"] < samples) {
        sample_count["invalid_validation"]++
        sample["invalid_validation", sample_count["invalid_validation"]] = $0
      }
    }

    if (validation == "ambient_rejected" && ambient == "") {
      rejected_without_ambient++
      if (sample_count["rejected_without_ambient"] < samples) {
        sample_count["rejected_without_ambient"]++
        sample["rejected_without_ambient", sample_count["rejected_without_ambient"]] = $0
      }
    }

    if (authority == "target_materialization" && map_source != "target_map") {
      target_without_target_map_source++
      if (sample_count["target_without_target_map_source"] < samples) {
        sample_count["target_without_target_map_source"]++
        sample["target_without_target_map_source", sample_count["target_without_target_map_source"]] = $0
      }
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" rows + 0
    print "malformed=" malformed + 0
    print "invalid_validation=" invalid_validation + 0
    print "rejected_without_ambient=" rejected_without_ambient + 0
    print "target_without_target_map_source=" target_without_target_map_source + 0

    print ""
    print "## Authorities"
    for (a in authority_count) {
      print a "=" authority_count[a]
    }

    print ""
    print "## Map Sources"
    for (m in map_source_count) {
      print m "=" map_source_count[m]
    }

    print ""
    print "## Validations"
    for (v in validation_count) {
      print v "=" validation_count[v]
    }

    print ""
    print "## Lifetime Regions"
    for (l in lifetime_count) {
      print l "=" lifetime_count[l]
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
    print "## Invalid Validation Samples"
    if ((sample_count["invalid_validation"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["invalid_validation"]; i++) {
        print sample["invalid_validation", i]
      }
    }

    print ""
    print "## Rejected Without Ambient Samples"
    if ((sample_count["rejected_without_ambient"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["rejected_without_ambient"]; i++) {
        print sample["rejected_without_ambient", i]
      }
    }

    print ""
    print "## Target Without Target-Map Source Samples"
    if ((sample_count["target_without_target_map_source"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["target_without_target_map_source"]; i++) {
        print sample["target_without_target_map_source", i]
      }
    }

    print ""
    print "## Last Row"
    print last_row

    if ((rows + 0) == 0 || (malformed + 0) != 0 ||
        (invalid_validation + 0) != 0 ||
        (rejected_without_ambient + 0) != 0) {
      exit 1
    }
  }
' "$LOG"

if [[ $compiler_rc -ne 0 ]]; then
  echo ""
  echo "## Nonzero Compiler Tail"
  tail -80 "$LOG" || true
fi
