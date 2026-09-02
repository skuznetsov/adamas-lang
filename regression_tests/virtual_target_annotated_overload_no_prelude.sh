#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d /tmp/adamas_vtr_annotated_overload.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Object
  def render : Int32
    11
  end

  def render(sink : Sink) : Int32
    22
  end
end

class Reference < Object
end

class Sink < Reference
end

class FancySink < Sink
end

class Box(T) < Reference
end

def invoke(value : Object, sink : FancySink) : Int32
  value.render(sink)
end

LibC.exit(invoke(Box(Int32).new, FancySink.new) == 22 ? 0 : 1)
CR

ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
    "$TMP_DIR/repro.cr" --no-prelude --emit hir --no-link -o "$TMP_DIR/out" \
    >"$TMP_DIR/compile.log" 2>&1

HIR="$TMP_DIR/out.hir"
if [[ ! -s "$HIR" ]]; then
  echo "annotated virtual overload guard failed: missing HIR" >&2
  tail -80 "$TMP_DIR/compile.log" >&2 || true
  exit 1
fi

if ! grep -Fq 'func @Object#render$Sink' "$HIR"; then
  echo "annotated virtual overload guard failed: missing selected overload" >&2
  grep -n 'render' "$HIR" >&2 || true
  exit 1
fi

if grep -Fq 'func @Object#render(' "$HIR"; then
  echo "annotated virtual overload guard failed: materialized unsuffixed sibling" >&2
  grep -n 'render' "$HIR" >&2 || true
  exit 1
fi

if grep -Fq 'func @Box(Int32)#render' "$HIR"; then
  echo "annotated virtual overload guard failed: materialized generic wrapper" >&2
  grep -n 'render' "$HIR" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
  "$TMP_DIR/repro.cr" --no-prelude -o "$TMP_DIR/repro" \
  >"$TMP_DIR/build.log" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/repro" 5 512 \
  >"$TMP_DIR/run.log" 2>&1

echo "virtual_target_annotated_overload_no_prelude_ok"
