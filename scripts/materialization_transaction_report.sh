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
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/materialization-transaction.XXXXXX")"
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
ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${COMPILE_ARGS[@]}" >"$LOG" 2>&1
compiler_rc=$?
set -e

if ! grep -q '^\[MAT_TX\]' "$LOG"; then
  echo "FAIL: no [MAT_TX] materialization transaction rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -100 "$LOG" >&2 || true
  exit 1
fi

echo "# Materialization Transaction Report"
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

  /^\[MAT_TX\]/ {
    row_count++
    phase = field("phase")
    status = field("identity_status")
    relation = field("symbol_relation")
    contract = field("required_contract")
    requested = field("requested")
    target = field("target")
    body = field("body_symbol")
    call = field("call_symbol_hint")
    last_row = $0

    phase_count[phase]++
    status_count[status]++
    relation_count[relation]++
    contract_count[contract]++

    if (status == "" || relation == "" || requested == "" || target == "" || body == "" || call == "") {
      malformed++
      if (sample_count["malformed"] < samples) {
        sample_count["malformed"]++
        sample["malformed", sample_count["malformed"]] = $0
      }
    }

    if (status != "exact") {
      if (sample_count[status] < samples) {
        sample_count[status]++
        sample[status, sample_count[status]] = "phase=" phase " relation=" relation " contract=" contract " requested=" requested " target=" target " body=" body " call=" call
      }
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" row_count + 0
    print "malformed=" malformed + 0

    print ""
    print "## Identity Status"
    for (s in status_count) {
      print s "=" status_count[s]
    }

    print ""
    print "## Symbol Relations"
    for (r in relation_count) {
      print r "=" relation_count[r]
    }

    print ""
    print "## Required Contracts"
    for (c in contract_count) {
      print c "=" contract_count[c]
    }

    print ""
    print "## Phases"
    for (p in phase_count) {
      print p "=" phase_count[p]
    }

    print ""
    print "## Non-Exact Samples"
    for (s in status_count) {
      if (s != "exact") {
        print "### " s
        if ((sample_count[s] + 0) == 0) {
          print "(none)"
        } else {
          for (i = 1; i <= sample_count[s]; i++) {
            print sample[s, i]
          }
        }
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
