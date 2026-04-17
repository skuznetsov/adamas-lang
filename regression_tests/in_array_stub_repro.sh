#!/usr/bin/env bash
# Known-red reducer for: Int32#in?$Array(Int32) → STUB CALLED runtime abort.
# Documented in ../KNOWN_BUGS.md.
#
# Exit contract:
#   0 — reproduced: the EXACT expected STUB signature was observed.
#   1 — not reproduced: binary ran cleanly (bug likely fixed).
#   2 — invalid invocation (missing compiler arg).
#   >2 — unexpected failure (compile error, different STUB, segfault, timeout,
#        etc.). These are NOT treated as reproductions — they flag a distinct
#        bug that shouldn't be masked by this known-red guard.
set -euo pipefail

EXPECTED_STUB='STUB CALLED: Int32$Hin$Q$$Array$LInt32$R'

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/in_array_stub.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
a = [1, 2, 3]
puts 2.in?(a)
r = 1..3
puts 2.in?(r)
CR

compile_cmd=()
if [[ "$(basename "$COMPILER")" == "crystal" ]]; then
  compile_cmd=("$COMPILER" build "$SRC" -o "$BIN")
else
  compile_cmd=("$COMPILER" "$SRC" -o "$BIN")
fi

set +e
"${compile_cmd[@]}" >"$TMP_DIR/compile.out" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "unexpected: compile failed with status=$compile_status" >&2
  tail -20 "$TMP_DIR/compile.out" >&2
  exit 3
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 256 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if grep -qF "$EXPECTED_STUB" "$RUN_LOG"; then
  echo "reproduced: $EXPECTED_STUB"
  exit 0
fi

if [[ $run_status -eq 0 ]]; then
  echo "not reproduced: ran cleanly with exit 0 (bug likely fixed)"
  cat "$RUN_LOG"
  exit 1
fi

echo "unexpected: abnormal exit ($run_status) without expected STUB" >&2
echo "expected signature: $EXPECTED_STUB" >&2
echo "--- run log tail ---" >&2
tail -20 "$RUN_LOG" >&2
exit 4
