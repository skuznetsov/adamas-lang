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

if ! grep -q '^\[MAT_EMIT\]' "$LOG"; then
  echo "FAIL: no [MAT_EMIT] materialization emitted-call rows emitted" >&2
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
    tx = field("tx")
    phase = field("phase")
    status = field("identity_status")
    relation = field("symbol_relation")
    contract = field("required_contract")
    requested = field("requested")
    target = field("target")
    body = field("body_symbol")
    call = field("call_symbol_hint")
    selected_def = field("selected_def")
    state_scope = field("state_scope")
    map_source = field("map_source")
    materialization_action = field("materialization_action")
    last_row = $0

    phase_count[phase]++
    status_count[status]++
    relation_count[relation]++
    contract_count[contract]++
    state_scope_count[state_scope]++
    map_source_count[map_source]++
    materialization_action_count[materialization_action]++

    if (tx == "" || status == "" || relation == "" || requested == "" || target == "" || body == "" || call == "") {
      malformed++
      if (sample_count["malformed"] < samples) {
        sample_count["malformed"]++
        sample["malformed", sample_count["malformed"]] = $0
      }
    } else {
      tx_seen[tx] = 1
    }

    if (status != "exact") {
      if (sample_count[status] < samples) {
        sample_count[status]++
        sample[status, sample_count[status]] = "phase=" phase " relation=" relation " contract=" contract " requested=" requested " target=" target " body=" body " call=" call
      }
    }

    if (selected_def == "" || state_scope == "" || map_source == "" || materialization_action == "") {
      owner_malformed++
      if (sample_count["owner_malformed"] < samples) {
        sample_count["owner_malformed"]++
        sample["owner_malformed", sample_count["owner_malformed"]] = $0
      }
    }
  }

  /^\[MAT_EMIT\]/ {
    emit_count++
    tx = field("tx")
    kind = field("kind")
    emitted = field("emitted")
    ret = field("ret")
    argc = field("argc")
    arg_types = field("arg_types")
    body_present = field("body_present")

    emit_kind_count[kind]++
    last_emit_row = $0

    if (tx == "" || kind == "" || emitted == "" || ret == "" || argc == "" || body_present == "") {
      malformed_emit++
      if (sample_count["malformed_emit"] < samples) {
        sample_count["malformed_emit"]++
        sample["malformed_emit", sample_count["malformed_emit"]] = $0
      }
      next
    }

    if (tx == "none") {
      non_transaction_emit++
      if (sample_count["non_transaction_emit"] < samples) {
        sample_count["non_transaction_emit"]++
        sample["non_transaction_emit", sample_count["non_transaction_emit"]] = "kind=" kind " emitted=" emitted " ret=" ret " argc=" argc " arg_types=" arg_types
      }
    } else {
      transaction_emit++
      tx_emit_count[tx]++
      if (!(tx in tx_seen)) {
        unjoined_emit++
        if (sample_count["unjoined_emit"] < samples) {
          sample_count["unjoined_emit"]++
          sample["unjoined_emit", sample_count["unjoined_emit"]] = $0
        }
      }
    }
  }

  END {
    for (tx in tx_seen) {
      tx_distinct++
      if ((tx_emit_count[tx] + 0) > 0) {
        joined_tx++
      }
    }

    print ""
    print "## Counts"
    print "rows=" row_count + 0
    print "malformed=" malformed + 0
    print "emit_rows=" emit_count + 0
    print "malformed_emit=" malformed_emit + 0
    print "owner_malformed=" owner_malformed + 0
    print "transaction_ids=" tx_distinct + 0
    print "transaction_bound_emit_rows=" transaction_emit + 0
    print "non_transaction_emit_rows=" non_transaction_emit + 0
    print "joined_transactions=" joined_tx + 0
    print "unjoined_emit_rows=" unjoined_emit + 0

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
    print "## State Scopes"
    for (s in state_scope_count) {
      print s "=" state_scope_count[s]
    }

    print ""
    print "## Map Sources"
    for (m in map_source_count) {
      print m "=" map_source_count[m]
    }

    print ""
    print "## Materialization Actions"
    for (a in materialization_action_count) {
      print a "=" materialization_action_count[a]
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
    print "## Emit Kinds"
    for (k in emit_kind_count) {
      print k "=" emit_kind_count[k]
    }

    print ""
    print "## Non-Transaction Emit Samples"
    if ((sample_count["non_transaction_emit"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["non_transaction_emit"]; i++) {
        print sample["non_transaction_emit", i]
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
    print "## Malformed Emit Samples"
    if ((sample_count["malformed_emit"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["malformed_emit"]; i++) {
        print sample["malformed_emit", i]
      }
    }

    print ""
    print "## Owner Malformed Samples"
    if ((sample_count["owner_malformed"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["owner_malformed"]; i++) {
        print sample["owner_malformed", i]
      }
    }

    print ""
    print "## Unjoined Emit Samples"
    if ((sample_count["unjoined_emit"] + 0) == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= sample_count["unjoined_emit"]; i++) {
        print sample["unjoined_emit", i]
      }
    }

    print ""
    print "## Last Row"
    print last_row

    print ""
    print "## Last Emit Row"
    print last_emit_row

    if ((row_count + 0) == 0 || (emit_count + 0) == 0 || (malformed + 0) != 0 ||
        (malformed_emit + 0) != 0 || (owner_malformed + 0) != 0 || (transaction_emit + 0) == 0 ||
        (joined_tx + 0) == 0 || (unjoined_emit + 0) != 0) {
      exit 1
    }
  }
' "$LOG"

if [[ $compiler_rc -ne 0 ]]; then
  echo ""
  echo "## Nonzero Compiler Tail"
  tail -80 "$LOG" || true
fi
