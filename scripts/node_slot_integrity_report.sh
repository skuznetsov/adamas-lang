#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler> [source.cr [compiler-args...]]" >&2
  echo "requires: compiler built with -Ddebug_hooks" >&2
  echo "env: TIMEOUT=180 MEM_MB=4096 SAMPLES=8" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
shift

TIMEOUT="${TIMEOUT:-180}"
MEM_MB="${MEM_MB:-4096}"
SAMPLES="${SAMPLES:-8}"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/node-slot-integrity.XXXXXX")"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ $# -eq 0 ]]; then
  SRC="$TMP_DIR/repro.cr"
  OUT="$TMP_DIR/repro"
  cat > "$SRC" <<'CR'
def identity(x)
  x
end

identity(1)
CR
  COMPILE_ARGS=("$SRC" --no-prelude -o "$OUT")
else
  SRC="$1"
  shift
  COMPILE_ARGS=("$SRC" "$@")
fi

set +e
ADAMAS_NODE_SLOT_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${COMPILE_ARGS[@]}" >"$LOG" 2>&1
compiler_rc=$?
set -e

if ! grep -q '^\[NODE_SLOT\]' "$LOG"; then
  echo "FAIL: no [NODE_SLOT] rows emitted" >&2
  echo "hint: build the compiler with -Ddebug_hooks" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

echo "# NodeSlot Integrity Report"
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

  /^\[NODE_SLOT\]/ {
    row_count++
    role = field("role")
    label = field("label")
    fn_name = field("func")
    in_range = field("in_range")
    slot_present = field("slot_present")
    node_present = field("node_present")
    null_id = field("null")
    invalid_id = field("invalid")
    ref_origin = field("ref_origin")
    last_row = $0

    role_count[role]++
    label_count[label]++
    origin_count[ref_origin]++

    if (null_id == "1") {
      bucket = "null_expr"
    } else if (invalid_id == "1") {
      bucket = "invalid_expr"
    } else if (in_range != "1") {
      bucket = "out_of_range"
    } else if (slot_present != "1") {
      bucket = "missing_slot"
    } else if (node_present != "1") {
      bucket = "missing_node_payload"
    } else {
      bucket = "healthy_present"
    }

    bucket_count[bucket]++
    if (sample_count[bucket] < samples) {
      sample_count[bucket]++
      sample[bucket, sample_count[bucket]] = "role=" role " label=" label " func=" fn_name " ref_origin=" ref_origin " in_range=" in_range " slot_present=" slot_present " node_present=" node_present
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" row_count + 0
    print "healthy_present=" bucket_count["healthy_present"] + 0
    print "missing_node_payload=" bucket_count["missing_node_payload"] + 0
    print "missing_slot=" bucket_count["missing_slot"] + 0
    print "out_of_range=" bucket_count["out_of_range"] + 0
    print "invalid_expr=" bucket_count["invalid_expr"] + 0
    print "null_expr=" bucket_count["null_expr"] + 0

    print ""
    print "## Roles"
    for (r in role_count) {
      print r "=" role_count[r]
    }

    print ""
    print "## Ref Origins"
    for (origin in origin_count) {
      print origin "=" origin_count[origin]
    }

    print ""
    print "## Labels"
    for (lbl in label_count) {
      print lbl "=" label_count[lbl]
    }

    print ""
    print "## Non-Healthy Samples"
    buckets[1] = "missing_node_payload"
    buckets[2] = "missing_slot"
    buckets[3] = "out_of_range"
    buckets[4] = "invalid_expr"
    buckets[5] = "null_expr"
    for (bi = 1; bi <= 5; bi++) {
      bucket = buckets[bi]
      print "### " bucket
      if ((sample_count[bucket] + 0) == 0) {
        print "(none)"
      } else {
        for (i = 1; i <= sample_count[bucket]; i++) {
          print sample[bucket, i]
        }
      }
    }

    print ""
    print "## Last Row"
    print last_row

    if ((row_count + 0) == 0) {
      exit 1
    }
  }
' "$LOG"

if [[ $compiler_rc -ne 0 ]]; then
  echo ""
  echo "## Nonzero Compiler Tail"
  tail -60 "$LOG" || true
fi
