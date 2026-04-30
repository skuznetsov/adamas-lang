#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/p2_elsif_short_circuit.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
@[Acyclic]
class Box
end

lib LibC
  fun abort : NoReturn
end

def first(box : Box) : Bool
  LibC.abort
  false
end

def second(box : Box) : Bool
  LibC.abort
  true
end

def probe(name : Box?) : Int32
  if name && first(name)
    1
  elsif name && second(name)
    2
  else
    3
  end
end

LibC.abort if probe(nil) != 3
CR

if ! "$COMPILER" "$SRC" --no-prelude -o "$BIN" >"$COMPILE_LOG" 2>&1; then
  echo "p2_elsif_short_circuit_condition_no_prelude_failed: compile failed" >&2
  cat "$COMPILE_LOG" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1; then
  echo "p2_elsif_short_circuit_condition_no_prelude_failed: runtime failed" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_elsif_short_circuit_condition_no_prelude_ok"
