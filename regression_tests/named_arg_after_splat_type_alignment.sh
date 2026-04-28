#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
TMP_DIR="$(mktemp -d /tmp/cv2_named_after_splat.XXXXXX)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/repro.cr" <<'CR'
class IO
end

class E
  def inspect_with_backtrace(io : IO)
  end
end

class A
end

def buffered(message : String, *args, exception = nil)
  if exception
    exception.inspect_with_backtrace(IO.new)
  end
end

buffered("x", A.new, exception: E.new)
CR

CRYSTAL_V2_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 512 \
    "$TMP_DIR/repro.cr" --no-prelude --emit hir --no-link -o "$TMP_DIR/out" \
    > "$TMP_DIR/compile.log" 2>&1

HIR="$TMP_DIR/out.hir"
if [[ ! -s "$HIR" ]]; then
  echo "named_arg_after_splat_type_alignment_failed: missing HIR" >&2
  tail -80 "$TMP_DIR/compile.log" >&2 || true
  exit 1
fi

if grep -q 'Tuple#inspect_with_backtrace' "$HIR"; then
  echo "named_arg_after_splat_type_alignment_failed: exception param took splat tuple type" >&2
  grep -n 'inspect_with_backtrace' "$HIR" >&2 || true
  exit 1
fi

if ! grep -q 'E#inspect_with_backtrace\$IO' "$HIR"; then
  echo "named_arg_after_splat_type_alignment_failed: missing E#inspect_with_backtrace call" >&2
  grep -n 'inspect_with_backtrace' "$HIR" >&2 || true
  exit 1
fi

echo "named_arg_after_splat_type_alignment_ok"
