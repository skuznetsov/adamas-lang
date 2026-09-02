#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d /tmp/adamas_nilable_string_ne.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def optional(flag : Bool) : String | Nil
  if flag
    "previous"
  else
    nil
  end
end

def register_like(flag : Bool, target : String) : Bool
  previous = optional(flag)
  marker = target
  previous != marker
end

def register_like_explicit(flag : Bool, target : String) : Bool
  previous = optional(flag)
  previous.!=(target)
end

LibC.exit(register_like(true, "previous") ? 1 : (register_like_explicit(true, "previous") ? 1 : 0))
CR

ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
    "$TMP_DIR/repro.cr" --no-prelude --emit hir --no-link -o "$TMP_DIR/out" \
    >"$TMP_DIR/compile.log" 2>&1

HIR="$TMP_DIR/out.hir"
if [[ ! -s "$HIR" ]]; then
  echo "nilable String inequality regression: missing HIR" >&2
  cat "$TMP_DIR/compile.log" >&2
  exit 1
fi

if ! grep -Fq '__adamas_string_eq' "$HIR"; then
  echo "nilable String inequality regression: missing String equality intrinsic" >&2
  grep -n -E '!=|string_eq' "$HIR" >&2 || true
  exit 1
fi

if grep -Fq 'Object#!=$String' "$HIR" || grep -Fq 'func @!=$String' "$HIR"; then
  echo "nilable String inequality regression: leaked source-level inequality demand" >&2
  grep -n -E 'Object#!=|func @!=' "$HIR" >&2 || true
  exit 1
fi

cat >"$TMP_DIR/broad_object.cr" <<'CR'
class Object
  def ==(other : Object) : Bool
    false
  end

  def !=(other : Object) : Bool
    !(self == other)
  end
end

class Reference < Object
end

left = "x".as(Object)
left != "y"
CR

ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
    "$TMP_DIR/broad_object.cr" --no-prelude --emit hir --no-link -o "$TMP_DIR/broad_object" \
    >"$TMP_DIR/broad_object_compile.log" 2>&1

BROAD_HIR="$TMP_DIR/broad_object.hir"
if ! grep -Fq 'Object#!=$String' "$BROAD_HIR"; then
  echo "nilable String inequality regression: broad Object dispatch was pruned" >&2
  grep -n -E 'Object#!=|string_eq' "$BROAD_HIR" >&2 || true
  exit 1
fi

if grep -Fq '__adamas_string_eq' "$BROAD_HIR"; then
  echo "nilable String inequality regression: broad Object dispatch used String intrinsic" >&2
  grep -n -E 'Object#!=|string_eq' "$BROAD_HIR" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
  "$TMP_DIR/repro.cr" --no-prelude -o "$TMP_DIR/repro" \
  >"$TMP_DIR/build.log" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/repro" 5 512 \
  >"$TMP_DIR/run.log" 2>&1

echo "nilable_string_inequality_intrinsic_no_prelude_ok"
