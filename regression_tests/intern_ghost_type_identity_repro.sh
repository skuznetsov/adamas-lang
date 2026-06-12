#!/usr/bin/env bash
# Ghost type identities (B1b, 2026-06-12): one type name must intern to ONE
# TypeRef id.
#
# An ivar annotation naming a generic instantiation BEFORE its template is
# registered interned a kind=Generic placeholder; the later concrete
# registration (kind=Struct/Class, same name + same type params) minted a
# SECOND id ("ghost"). Stale type caches then kept both ids alive in one
# compile — the Slice(UInt8) slot-8-vs-16 layout family (see
# docs/layout_freeze_proposal.md). Post-fix, intern_type upgrades the
# placeholder entry in place and returns the original id.
#
# Oracle: layout probe registration trace. Expect NO intern_type.ghost row
# and at least one intern_type.upgrade row for the reducer's generic struct.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/intern-ghost-identity.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "usage: $0 <adamas-compiler>" >&2
  echo "missing executable compiler: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
TSV="$TMP_DIR/probe.tsv"

# Box(Int32) appears in the User ivar annotation BEFORE struct Box(T) is
# declared, so the annotation path interns it first.
cat >"$SRC" <<'CR'
class User
  @data : Box(Int32)

  def initialize(@data : Box(Int32))
  end

  def data : Box(Int32)
    @data
  end
end

struct Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end

u = User.new(Box(Int32).new(42))
exit(u.data.value == 42 ? 0 : 1)
CR

ADAMAS_LAYOUT_PROBE=1 ADAMAS_LAYOUT_PROBE_FILE="$TSV" \
ADAMAS_LAYOUT_PROBE_TRACE='Box(' \
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 2048 \
  "$SRC" --no-prelude -o "$OUT" >"$LOG" 2>&1 || {
  echo "compile failed" >&2
  cat "$LOG" >&2
  exit 2
}

if [[ ! -s "$TSV" ]]; then
  echo "probe trace produced no rows — oracle broken (ADAMAS_LAYOUT_PROBE wiring?)" >&2
  exit 2
fi

if awk -F'\t' '$2=="intern_type.ghost" && $5=="Box(Int32)"{found=1} END{exit found?0:1}' "$TSV"; then
  echo "open bug reproduced: Box(Int32) interned under two TypeRef ids (ghost identity)" >&2
  grep "intern_type" "$TSV" >&2
  exit 1
fi

if ! awk -F'\t' '$2=="intern_type.upgrade" && $5=="Box(Int32)"{found=1} END{exit found?0:1}' "$TSV"; then
  echo "expected an intern_type.upgrade row for Box(Int32) (kind-upgrade path did not fire)" >&2
  grep "intern_type" "$TSV" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$TMP_DIR/run.log" 2>&1 || {
  echo "reducer binary failed at runtime" >&2
  cat "$TMP_DIR/run.log" >&2
  exit 1
}

echo "fixed: Box(Int32) keeps one TypeRef id (placeholder upgraded in place)"
