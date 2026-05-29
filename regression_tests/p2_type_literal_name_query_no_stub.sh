#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:-bin/adamas}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/cv2_type_literal_name_query.XXXXXX)"
SRC="$TMP_DIR/type_literal_name_query.cr"
OUT="$TMP_DIR/type_literal_name_query"
LL="$OUT.ll"
LOG="$TMP_DIR/type_literal_name_query.log"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_type_literal_name_query_no_stub] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
class NameProbe
end

def probe
  NameProbe.to_s
  NameProbe.name
end
CR

set +e
"$ROOT/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  "$SRC" --no-prelude --emit llvm-ir --no-link -o "$OUT" \
  >"$LOG" 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "p2_type_literal_name_query_no_stub_failed: compiler failed while emitting LLVM IR" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if [[ ! -s "$LL" ]]; then
  echo "p2_type_literal_name_query_no_stub_failed: missing LLVM IR" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if grep -Fq 'NameProbe$Dto_s' "$LL"; then
  echo "p2_type_literal_name_query_no_stub_failed: NameProbe.to_s lowered to static stub target" >&2
  grep -Fn 'NameProbe$Dto_s' "$LL" >&2 || true
  exit 1
fi

if grep -Fq 'NameProbe$Dname' "$LL"; then
  echo "p2_type_literal_name_query_no_stub_failed: NameProbe.name lowered to static stub target" >&2
  grep -Fn 'NameProbe$Dname' "$LL" >&2 || true
  exit 1
fi

if ! grep -Fq 'c"NameProbe\00"' "$LL"; then
  echo "p2_type_literal_name_query_no_stub_failed: missing NameProbe literal string" >&2
  exit 1
fi

echo "p2_type_literal_name_query_no_stub_ok"
