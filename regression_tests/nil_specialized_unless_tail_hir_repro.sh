#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SOURCE="$ROOT_DIR/regression_tests/nil_specialized_unless_tail_hir_repro.cr"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/nil_specialized_unless_tail.XXXXXX")"
PROBE_SOURCE="$WORKDIR/probe.cr"
PROBE_HIR="$WORKDIR/probe.hir"
NIL_HIR="$WORKDIR/nil.hir"
NIL_ELSE_HIR="$WORKDIR/nil_else.hir"
LIVE_HIR="$WORKDIR/live.hir"
LOG="$WORKDIR/compile.log"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

cp "$SOURCE" "$PROBE_SOURCE"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 2048 \
  "$PROBE_SOURCE" --emit hir --no-link >"$LOG" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "reproduced: compiler lowered the unreachable Nil#any? tail" >&2
  tail -n 120 "$LOG" >&2
  exit 1
fi

if [[ ! -f "$PROBE_HIR" ]]; then
  echo "inconclusive: compiler succeeded without emitting the expected HIR" >&2
  tail -n 120 "$LOG" >&2
  exit 2
fi

awk '
  /^func @/ {
    if (capture) exit
    if (index($0, "func @nil_guarded_any?$Nil") == 1) capture = 1
  }
  capture { print }
' "$PROBE_HIR" >"$NIL_HIR"

if [[ ! -s "$NIL_HIR" ]]; then
  echo "inconclusive: Nil-specialized probe function was not emitted" >&2
  exit 2
fi

if rg -q '#any\?\$|array_size|index_get|binop Gt' "$NIL_HIR"; then
  echo "reproduced: Nil-specialized function still contains the unreachable any? tail" >&2
  rg -n '#any\?\$|array_size|index_get|binop Gt' "$NIL_HIR" >&2
  exit 1
fi

awk '
  /^func @/ {
    if (capture) exit
    if (index($0, "func @nil_guarded_else?$Nil") == 1) capture = 1
  }
  capture { print }
' "$PROBE_HIR" >"$NIL_ELSE_HIR"

if [[ ! -s "$NIL_ELSE_HIR" ]]; then
  echo "inconclusive: static-true Nil probe function was not emitted" >&2
  exit 2
fi

if rg -q '#includes\?\$|string_includes' "$NIL_ELSE_HIR"; then
  echo "reproduced: static-true unless branch retained its impossible includes? body" >&2
  rg -n '#includes\?\$|string_includes' "$NIL_ELSE_HIR" >&2
  exit 1
fi

if ! rg -q 'literal true' "$NIL_ELSE_HIR"; then
  echo "inconclusive: static-true unless branch lost its reachable else value" >&2
  exit 2
fi

awk '
  /^func @/ {
    if (capture) exit
    if (index($0, "func @live_guarded_any?$") == 1) capture = 1
  }
  capture { print }
' "$PROBE_HIR" >"$LIVE_HIR"

if [[ ! -s "$LIVE_HIR" ]]; then
  echo "inconclusive: live control function was not emitted" >&2
  exit 2
fi

if rg -q 'Nil#any\?\$' "$LIVE_HIR"; then
  echo "reproduced: live control dispatches any? through Nil" >&2
  rg -n 'Nil#any\?\$' "$LIVE_HIR" >&2
  exit 1
fi

if ! rg -q '#any\?\$block' "$LIVE_HIR" &&
   ! (rg -q 'array_size' "$LIVE_HIR" &&
      rg -q 'index_get' "$LIVE_HIR" &&
      rg -q 'binop Gt' "$LIVE_HIR"); then
  echo "inconclusive: live control lost its reachable any? work" >&2
  exit 2
fi

echo "nil_specialized_unless_tail_hir_ok"
