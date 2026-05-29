#!/usr/bin/env bash
# Regression: block-param inference for class methods must use the callee
# owner as `self` when an untyped block delegates through another class method.
#
# Pre-fix shape:
#   FileLike.open { |file| file.read(buffer) }
#   FileLike.open -> open_internal { |file| yield file }
#
# `infer_yield_param_types_from_body` used the caller's @current_class when a
# class method had no instance receiver. The nested `open_internal` block param
# inference then lost the callee owner context and the outer block proc kept
# `file` as Pointer. The real stage2 symptom was `CLI#file_sha256` lowering
# `File.open { |file| file.read(buffer) }` to Pointer#read(Slice(UInt8)).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_class_method_nested_yield_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/compile.log"
HIR="$OUT.hir"

cat >"$SRC" <<'CR'
class Object
end

class Reference < Object
end

class Buffer < Reference
end

class Reader < Reference
  def read(buffer : Buffer) : Int32
    7
  end
end

class FileLike < Reference
  def self.open(&)
    open_internal do |file|
      yield file
    end
  end

  protected def self.open_internal(&)
    file = Reader.new
    yield file
  end
end

def drive : Int32
  buffer = Buffer.new
  FileLike.open do |file|
    file.read(buffer)
  end
end

drive
CR

CRYSTAL_V2_STOP_AFTER_HIR=1 CRYSTAL_V2_DISABLE_INLINE_YIELD=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 1024 \
  "$SRC" --no-prelude --emit hir -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$HIR" ]]; then
  echo "p2_class_method_nested_yield_block_param_failed: missing HIR artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

reader_type="$(awk '/= Class Reader$/ { sub("type\\.", "", $1); print $1; exit }' "$HIR")"
if [[ -z "$reader_type" ]]; then
  echo "p2_class_method_nested_yield_block_param_failed: could not find Reader type id" >&2
  sed -n '1,40p' "$HIR" >&2
  exit 1
fi

if grep -Eq 'func @__crystal_block_proc_[0-9]+\(%0: 18\)' "$HIR"; then
  echo "p2_class_method_nested_yield_block_param_failed: outer block proc kept Pointer param" >&2
  grep -n 'func @__crystal_block_proc' "$HIR" >&2 || true
  exit 1
fi

if ! grep -Eq "func @__crystal_block_proc_[0-9]+\\(%0: ${reader_type}\\)" "$HIR"; then
  echo "p2_class_method_nested_yield_block_param_failed: outer block proc was not typed as Reader" >&2
  grep -n 'func @__crystal_block_proc' "$HIR" >&2 || true
  exit 1
fi

if ! grep -q 'Reader#read$Buffer' "$HIR"; then
  echo "p2_class_method_nested_yield_block_param_failed: Reader#read(Buffer) dispatch missing" >&2
  exit 1
fi

echo "p2_class_method_nested_yield_block_param_no_prelude_ok"
