#!/usr/bin/env bash
# HIR no-prelude guard: `case v = @union; when T` must narrow `v` before use.
#
# Regression shape:
#   @raw : Int32 | String | Nil
#   @value : String?
#   case v = @raw
#   when String
#     @value = v
#   end
#
# The root failure left `v` typed as the broad union inside the String branch.
# Lowering then stored the wide tagged union into a pointer-backed String? ivar,
# and the getter later returned the union header as a String pointer.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_case_union_ivar_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/case_union_ivar.cr"
OUT="$TMP_DIR/case_union_ivar"
LOG="$TMP_DIR/run_safe.log"
HIR="$OUT.hir"

cat >"$SRC" <<'CR'
class Carrier
  @raw : Int32 | String | Nil
  @value : String? = nil

  def initialize(@raw : Int32 | String | Nil)
    sync
  end

  def value
    @value
  end

  private def sync
    case v = @raw
    when String
      @value = v
    when Nil
    else
    end
  end
end

Carrier.new("abc").value
CR

ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$HIR" ]]; then
  echo "p2 case union ivar narrowing regression: missing HIR artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

UNWRAP_ID="$(
  awk '
    /^func @Carrier#sync/ {in_sync=1}
    in_sync && /union_unwrap/ {
      if (match($0, /%[0-9]+ = union_unwrap/)) {
        print substr($0, RSTART + 1, RLENGTH - 16)
        exit
      }
    }
    in_sync && /^}/ {exit}
  ' "$HIR"
)"

if [[ -z "$UNWRAP_ID" ]]; then
  echo "p2 case union ivar narrowing regression: String branch did not unwrap the union subject" >&2
  grep -n 'Carrier#sync' -A40 "$HIR" >&2 || true
  exit 1
fi

if grep -Eq 'field_set %0\.@@value = %3\b' "$HIR"; then
  echo "p2 case union ivar narrowing regression: @value stores the broad case subject" >&2
  grep -n 'Carrier#sync' -A40 "$HIR" >&2 || true
  exit 1
fi

echo "p2_case_union_ivar_narrowing_no_prelude_ok"
