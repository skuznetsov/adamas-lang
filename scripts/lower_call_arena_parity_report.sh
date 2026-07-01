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
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/lower-call-arena-parity.XXXXXX")"
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
ADAMAS_LOWER_CALL_ARENA_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${COMPILE_ARGS[@]}" >"$LOG" 2>&1
compiler_rc=$?
set -e

if ! grep -q '^\[LC_ARENA\]' "$LOG"; then
  echo "FAIL: no [LC_ARENA] rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'kind=expr' "$LOG"; then
  echo "FAIL: no lower-call expr rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'ref_origin=' "$LOG" || ! grep -q 'ref_span=' "$LOG"; then
  echo "FAIL: lower-call expr rows do not include AstNodeRef fields" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

echo "# LowerCall Arena Parity Report"
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

  /^\[LC_ARENA\]/ {
    kind = field("kind")
    if (kind == "phase") {
      phase_count++
      next
    }
    if (kind != "expr") {
      next
    }

    expr_count++
    current = field("current")
    preferred = field("preferred")
    owner = field("owner")
    current_has = field("current_has")
    preferred_has = field("preferred_has")
    owner_has = field("owner_has")
    label = field("label")
    ref_origin = field("ref_origin")
    ref_span = field("ref_span")
    fn_name = field("func")
    last_expr = $0

    current_preferred_same = (current == preferred)
    preferred_owner_same = (preferred == owner)
    current_owner_same = (current == owner)
    all_have = (current_has == "1" && preferred_has == "1" && owner_has == "1")

    if (current_preferred_same && preferred_owner_same && all_have) {
      bucket = "agree_all_have"
    } else if (current_preferred_same && preferred_owner_same) {
      bucket = "agree_missing_has"
    } else if (current_preferred_same && !preferred_owner_same) {
      bucket = "ref_current_vs_heuristic_diverge"
    } else if (!current_preferred_same && preferred_owner_same) {
      bucket = "current_vs_ref_owner_diverge"
    } else {
      bucket = "three_way_diverge"
    }

    bucket_count[bucket]++
    label_count[label]++
    origin_count[ref_origin]++
    if (sample_count[bucket] < samples) {
      sample_count[bucket]++
      sample[bucket, sample_count[bucket]] = "label=" label " func=" fn_name " ref_origin=" ref_origin " ref_span=" ref_span " current_has=" current_has " preferred_has=" preferred_has " owner_has=" owner_has
    }
  }

  END {
    print ""
    print "## Counts"
    print "phase_rows=" phase_count + 0
    print "expr_rows=" expr_count + 0
    print "agree_all_have=" bucket_count["agree_all_have"] + 0
    print "agree_missing_has=" bucket_count["agree_missing_has"] + 0
    print "ref_current_vs_heuristic_diverge=" bucket_count["ref_current_vs_heuristic_diverge"] + 0
    print "current_vs_ref_owner_diverge=" bucket_count["current_vs_ref_owner_diverge"] + 0
    print "three_way_diverge=" bucket_count["three_way_diverge"] + 0

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
    print "## Divergence Samples"
    buckets[1] = "agree_missing_has"
    buckets[2] = "ref_current_vs_heuristic_diverge"
    buckets[3] = "current_vs_ref_owner_diverge"
    buckets[4] = "three_way_diverge"
    for (bi = 1; bi <= 4; bi++) {
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
    print "## Last Expr Row"
    print last_expr

    if ((expr_count + 0) == 0) {
      exit 1
    }
  }
' "$LOG"

if [[ $compiler_rc -ne 0 ]]; then
  echo ""
  echo "## Nonzero Compiler Tail"
  tail -60 "$LOG" || true
fi
