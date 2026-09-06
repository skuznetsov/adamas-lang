#!/usr/bin/env bash
# No-prelude regression for union Tuple#includes? lowering. The receiver is
# genuinely union-shaped at the call boundary, while every tuple element and
# the needle share the Char ABI. The predicate must use the tuple union inline
# dispatcher before generic receiver-contract admission.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
TIMEOUT_SECS="${TUPLE_UNION_INCLUDES_TIMEOUT:-10}"
MAX_MEM_MB="${TUPLE_UNION_INCLUDES_MAX_MEM:-1024}"
COMPILE_TIMEOUT_SECS="${TUPLE_UNION_INCLUDES_COMPILE_TIMEOUT:-120}"
COMPILE_MAX_MEM_MB="${TUPLE_UNION_INCLUDES_COMPILE_MAX_MEM:-8192}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple_union_includes_guard.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

SRC="$WORKDIR/repro.cr"
BIN="$WORKDIR/repro"
LOG="$WORKDIR/compile.log"

cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def choose(flag : Bool) : Tuple(Char) | Tuple(Char, Char)
  flag ? {'a'} : {'a', 'b'}
end

def includes_union(value : Tuple(Char) | Tuple(Char, Char), needle : Char) : Bool
  value.includes?(needle)
end

match_one = includes_union(choose(true), 'a')
match_two = includes_union(choose(false), 'b')
miss = includes_union(choose(false), 'z')
LibC.exit(match_one && match_two && !miss ? 0 : 81)
CR

if ! ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$COMPILER" \
  "$COMPILE_TIMEOUT_SECS" "$COMPILE_MAX_MEM_MB" \
  "$SRC" --no-prelude -o "$BIN" >"$LOG" 2>&1; then
  echo "FAIL: union Tuple#includes? did not compile" >&2
  tail -40 "$LOG" >&2
  exit 1
fi

RUN_LOG="$WORKDIR/run.log"
if ! ADAMAS_DISABLE_INLINE_YIELD=1 "$RUN_SAFE" "$BIN" \
  "$TIMEOUT_SECS" "$MAX_MEM_MB" >"$RUN_LOG" 2>&1; then
  echo "FAIL: union Tuple#includes? produced the wrong result" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "PASS: homogeneous primitive union Tuple#includes? lowers and runs"
