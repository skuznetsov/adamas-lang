#!/usr/bin/env bash
# Tier-1 no-prelude reducer for broad root-method virtual replay suppression.
#
# This isolates the bootstrap fanout shape where root fallback methods
# (`Object#to_s`, `Object#inspect`, `Reference#same?`) used to replay universal
# helper targets over generic descendants while lazy RTA was inactive. The
# demand-driven contract is that these records are preserved, but immediate
# broad-root replay is suppressed until lazy RTA can filter to live owners.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"

TIMEOUT_SEC="${P2_ROOT_REPLAY_TIMEOUT_SEC:-30}"
MEM_MB="${P2_ROOT_REPLAY_MEM_MB:-2048}"
PROCESS_DELTA_LIMIT="${P2_ROOT_REPLAY_PROCESS_DELTA_LIMIT:-120}"
TOTAL_FUNCTION_LIMIT="${P2_ROOT_REPLAY_TOTAL_FUNCTION_LIMIT:-180}"
OBJECT_REPLAY_LIMIT="${P2_ROOT_REPLAY_OBJECT_LIMIT:-15}"
REFERENCE_REPLAY_LIMIT="${P2_ROOT_REPLAY_REFERENCE_LIMIT:-8}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_root_self_replay_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/root_self_replay.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/run_safe.log"

cat >"$SRC" <<'CR'
class Object
  def to_s(io : Sink)
    inspect(io)
  end

  def inspect(io : Sink)
    to_s(io)
  end
end

class Reference < Object
  def object_id
    1_u64
  end

  def same?(other : Reference)
    object_id == other.object_id
  end
end

class Sink < Reference
end

class Box(T) < Reference
  def initialize(@value : T)
  end
end

class Pair(A, B) < Reference
  def initialize(@a : A, @b : B)
  end
end

io = Sink.new
x = Box(Box(Box(Pair(Int32, UInt64)))).new(
  Box(Box(Pair(Int32, UInt64))).new(
    Box(Pair(Int32, UInt64)).new(
      Pair(Int32, UInt64).new(1, 2_u64)
    )
  )
)

x.to_s(io)
x.inspect(io)
x.same?(x)
CR

DEBUG_VIRTUAL_TARGETS=1 \
CRYSTAL_V2_STOP_AFTER_HIR=1 \
CRYSTAL_V2_PHASE_STATS=1 \
CRYSTAL_V2_LOWER_PROGRESS=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

extract_delta() {
  local label="$1"
  local value
  value="$(grep -E "\\[PHASE_STATS\\] ${label}: [0-9]+ -> [0-9]+ \\(\\+[0-9]+\\)" "$LOG" \
    | tail -1 \
    | sed -E 's/.*\(\+([0-9]+)\).*/\1/' || true)"
  echo "${value:-0}"
}

process_delta="$(extract_delta process_pending)"
total_functions="$(grep -Eo 'Top type prefixes \([0-9]+ total functions\)' "$LOG" \
  | tail -1 \
  | sed -E 's/[^0-9]*([0-9]+).*/\1/' || true)"
total_functions="${total_functions:-0}"

object_records="$(grep -c '\[VIRTUAL_TARGET\] record parent=Object method=\(to_s\|inspect\)' "$LOG" || true)"
reference_records="$(grep -c '\[VIRTUAL_TARGET\] record parent=Reference method=object_id' "$LOG" || true)"
object_replays="$(grep -c '\[VIRTUAL_TARGET\] lower child=.* parent=Object' "$LOG" || true)"
reference_replays="$(grep -c '\[VIRTUAL_TARGET\] lower child=.* parent=Reference' "$LOG" || true)"

fail=0
if (( object_records < 2 )); then
  echo "p2 root self-replay oracle did not exercise Object#to_s/Object#inspect records" >&2
  fail=1
fi
if (( reference_records < 1 )); then
  echo "p2 root self-replay oracle did not exercise Reference#object_id record" >&2
  fail=1
fi
if (( process_delta > PROCESS_DELTA_LIMIT )); then
  echo "p2 root self-replay budget regression: process_pending delta ${process_delta} > ${PROCESS_DELTA_LIMIT}" >&2
  fail=1
fi
if (( total_functions > TOTAL_FUNCTION_LIMIT )); then
  echo "p2 root self-replay budget regression: total functions ${total_functions} > ${TOTAL_FUNCTION_LIMIT}" >&2
  fail=1
fi
if (( object_replays > OBJECT_REPLAY_LIMIT )); then
  echo "p2 root self-replay budget regression: Object replays ${object_replays} > ${OBJECT_REPLAY_LIMIT}" >&2
  fail=1
fi
if (( reference_replays > REFERENCE_REPLAY_LIMIT )); then
  echo "p2 root self-replay budget regression: Reference replays ${reference_replays} > ${REFERENCE_REPLAY_LIMIT}" >&2
  fail=1
fi

if (( fail != 0 )); then
  grep -E '\[VIRTUAL_TARGET\]|\[PHASE_STATS\]|\[LOWER\]' "$LOG" | tail -160 >&2 || true
  exit 1
fi

echo "p2_root_self_replay_no_prelude_ok process_delta=${process_delta} total=${total_functions} object_records=${object_records} reference_records=${reference_records} object_replays=${object_replays} reference_replays=${reference_replays}"
