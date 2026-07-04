#!/usr/bin/env bash
# Open frontier oracle: `def rand(max : Int) : Int` — the abstract `Int`
# return annotation resolves to Int32 ("abstract Int defaults to Int32",
# ast_to_hir builtin_type_ref_for), so rand$$Int64 truncates its i64 result
# through i32 (trunc + sext): rand(0x100000000) returns negative values.
# Dispatch itself is correct (rand_int$$Int64 is called) since the macro
# fresh-var adjacency fix; this guards the RETURN-width family.
#
# Red while the abstract-Int return collapse is unfixed; green after.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rand_int64_return.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
r = Random.new
ok = true
20.times do
  v = r.rand(0x100000000)
  unless 0 <= v < 0x100000000
    STDERR.puts "FAIL v=#{v}"
    ok = false
  end
end
STDERR.puts(ok ? "RANGE_OK" : "RANGE_BAD")
STDERR.flush
exit(ok ? 0 : 1)
CR

if ! "$COMPILER" "$SRC" -o "$OUT" >"$LOG" 2>&1; then
  echo "compile failed" >&2
  tail -20 "$LOG" >&2
  exit 1
fi

RUN_LOG="$TMP_DIR/run.log"
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 >"$RUN_LOG" 2>&1
if ! grep -q "RANGE_OK" "$RUN_LOG"; then
  echo "FAIL: rand(0x100000000) out of [0, 2^32) — abstract Int return truncation" >&2
  tail -10 "$RUN_LOG" >&2
  exit 1
fi

echo "PASS: rand(0x100000000) stays in range (Int return no longer collapses to Int32)"
