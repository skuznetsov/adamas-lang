#!/usr/bin/env bash
# Repro: record-generated initialize params must not take their names/types
# from a span-only lookup into the wrong retained macro-expansion buffer.
#
# Root cause (fixed): params of a macro-expanded def (record ToUnsignedInfo's
# auto initialize) are reparsed from retained generated text; their spans are
# bare offsets that do not identify WHICH retained buffer they index.
# parameter_name_string/parameter_type_annotation_string were called with
# fallback_to_slice=false, so the exact raw token slice was never computed and
# a plausible-looking slice from a FOREIGN expansion buffer won ("th_ind" out
# of "each_with_index"). Param names/types went garbage -> Bool args lowered
# via __adamas_bool_to_string -> ptrtoint ptr->i1 = 0 -> ToUnsignedInfo.invalid
# was always false -> ""/"abc".to_i? entered if-let with payload 0.
#
# GREEN: "".to_i? and "abc".to_i? skip the if-let; "64".to_i? enters with 64.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/record_init_span.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat > "$SRC" <<'CR'
v1 = "".to_i?
if b1 = v1
  STDERR.puts "c1: ENTERED #{b1}"
else
  STDERR.puts "c1: skipped"
end

v2 = "64".to_i?
if b2 = v2
  STDERR.puts "c2: entered #{b2}"
else
  STDERR.puts "c2: SKIPPED"
end

v3 = "abc".to_i?
if b3 = v3
  STDERR.puts "c3: ENTERED #{b3}"
else
  STDERR.puts "c3: skipped"
end
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$SRC" -o "$OUT" >"$LOG" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1 || true

fail=0
grep -q "c1: skipped" "$RUN_LOG" || { echo "RED: \"\".to_i? entered if-let"; fail=1; }
grep -q "c2: entered 64" "$RUN_LOG" || { echo "RED: \"64\".to_i? did not yield 64"; fail=1; }
grep -q "c3: skipped" "$RUN_LOG" || { echo "RED: \"abc\".to_i? entered if-let"; fail=1; }

if [[ "$fail" != "0" ]]; then
  echo "--- run log ---"
  cat "$RUN_LOG"
  exit 1
fi

echo "PASS: record-initialize params intact; to_i? nil semantics correct end-to-end"
