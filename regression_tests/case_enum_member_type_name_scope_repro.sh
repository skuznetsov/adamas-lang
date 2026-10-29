#!/usr/bin/env bash
# A `when` name that is both a member of the subject's enum and a type
# (`Kind::Bool` / `Bool`) is the member only where constant lookup reaches the
# member: inside the enum. Elsewhere original Crystal resolves `when Bool` to
# the type `::Bool`, so an enum subject never matches it. V2 preferred the
# member everywhere, so `case k when Bool` outside the enum matched Kind::Bool.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum-member-type-scope.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/t.cr" <<'CR'
enum Kind
  Bool
  Int32
  Other

  def primitive? : ::Bool
    case self
    when Bool, Int32 then true
    else                  false
    end
  end
end

def bare(k : Kind) : String
  case k
  when Bool then "type-bool"
  when Kind::Int32 then "member-int"
  else "other"
  end
end

STDERR.puts bare(Kind::Bool)
STDERR.puts bare(Kind::Int32)
STDERR.puts bare(Kind::Other)
STDERR.puts Kind::Bool.primitive?
STDERR.puts Kind::Int32.primitive?
STDERR.puts Kind::Other.primitive?
CR

printf '%s\n' other member-int other true true false > "$WORK_DIR/want"

stderr_of() {
  awk '/^=== STDERR ===$/ { on = 1; next } /^\[EXIT: / { on = 0 } on' "$1"
}

if [[ -n "$CRYSTAL_BIN" ]]; then
  if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build "$WORK_DIR/t.cr" \
      -o "$WORK_DIR/t.orig" > "$WORK_DIR/orig.log" 2>&1; then
    printf 'ORACLE FAIL: original rejects the program\n' >&2
    cat "$WORK_DIR/orig.log" >&2
    exit 2
  fi
  "$SAFE_RUNNER" "$WORK_DIR/t.orig" 5 256 > "$WORK_DIR/orig.run" 2>&1 || true
  if ! stderr_of "$WORK_DIR/orig.run" | diff -u "$WORK_DIR/want" - >&2; then
    printf 'ORACLE FAIL: original output differs\n' >&2
    exit 2
  fi
fi

"$SAFE_RUNNER" "$ADAMAS_BIN" 600 8192 "$WORK_DIR/t.cr" -o "$WORK_DIR/t.adamas" \
  > "$WORK_DIR/adamas.log" 2>&1 || true
if [[ ! -x "$WORK_DIR/t.adamas" ]]; then
  printf 'FAIL: compile failed\n' >&2
  grep -m3 -a 'rror' "$WORK_DIR/adamas.log" >&2 || tail -5 "$WORK_DIR/adamas.log" >&2
  exit 1
fi
"$SAFE_RUNNER" "$WORK_DIR/t.adamas" 5 256 > "$WORK_DIR/adamas.run" 2>&1 || true
if ! stderr_of "$WORK_DIR/adamas.run" | diff -u "$WORK_DIR/want" - >&2; then
  printf 'FAIL: output differs from original Crystal\n' >&2
  exit 1
fi
printf 'PASS enum member names resolve by lexical scope\n'
