#!/usr/bin/env bash
# Regex literals were compiled (pcre2_compile + JIT + malloc) on EVERY
# evaluation and never freed, so a literal in a hot loop grew RSS without
# bound (S3 self-host OOM: number-literal suffix `match(/..\z/i)` per literal).
# Each distinct literal must be compiled once and cached, like original Crystal.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/regex_literal_compile_once.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
def suffix?(s : String) : Bool
  !s.match(/_?(i8|i16|i32|i64|u8|f64)\z/).nil?
end

def digits?(s : String) : Bool
  !s.match(/\A[0-9]+\z/).nil?
end

hits = 0
digit_hits = 0
i = 0
while i < 600_000
  s = i.even? ? "12_i32" : "12"
  hits += 1 if suffix?(s)
  digit_hits += 1 if digits?(s)
  i += 1
end
exit 1 unless hits == 300_000
exit 2 unless digit_hits == 300_000
exit 0
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
    "$WORK_DIR/repro.cr" -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
# Per-evaluation compilation needs ~0.8 KB/eval (~900 MB here); cached needs a few MB.
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 30 128 >"$WORK_DIR/run.log" 2>&1; then
  grep -E '^\[(EXIT|KILL)' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo regex_literal_compile_once_repro_ok
