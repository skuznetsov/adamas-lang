#!/usr/bin/env bash
# HIR no-prelude guard: a multi-type `case` branch must narrow its subject
# before overload resolution, including calls with optional later parameters.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_case_multi_type_optional_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
HIR="$OUT.hir"

cat >"$SRC" <<'CR'
class Object
end

class String < Object
end

class Array(T) < Object
end

class Base < Object
end

class First < Base
end

class Second < Base
end

class Third < Base
end

class Probe < Object
  def source : Base
    First.new
  end

  def accept(
    member : First | Second | Third,
    owner : String,
    values : Array(Int32)?,
    offset : Pointer(Int32)?,
  ) : Nil
  end

  def inspect(owner : String, values : Array(Int32), offset : Pointer(Int32)) : Nil
    member = source
    case member
    when First, Second, Third
      accept(member, owner, values, offset)
    end
  end
end

offset = 0
Probe.new.inspect("owner", Array(Int32).new, pointerof(offset))
CR

ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$HIR" ]]; then
  echo "case multi-type optional-parameter regression: missing HIR artifact" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

EXPECTED='Probe#accept$First | Second | Third_String_Array(Int32)_Pointer(Int32)'
if ! grep -Fq "$EXPECTED" "$HIR"; then
  echo "case multi-type optional-parameter regression: call kept the broad Base subject" >&2
  grep -n 'Probe#accept' "$HIR" >&2 || true
  exit 1
fi

echo "p2_case_multi_type_optional_params_no_prelude_ok"
