#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d /tmp/cv2_dead_nil_branch.XXXXXX)"

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

def print_error_buffered(message : String, *args, exception = nil)
  buffered(message, *args, exception: exception)
end

print_error_buffered("x", A.new)
CR

CRYSTAL_V2_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 512 \
    "$TMP_DIR/repro.cr" --no-prelude --emit hir --no-link -o "$TMP_DIR/out" \
    > "$TMP_DIR/compile.log" 2>&1

HIR="$TMP_DIR/out.hir"
if [[ ! -s "$HIR" ]]; then
  echo "dead_nil_branch_after_splat_failed: missing HIR" >&2
  tail -80 "$TMP_DIR/compile.log" >&2 || true
  exit 1
fi

if grep -q 'Nil#inspect_with_backtrace' "$HIR"; then
  echo "dead_nil_branch_after_splat_failed: lowered unreachable nil inspect branch" >&2
  grep -n 'inspect_with_backtrace' "$HIR" >&2 || true
  exit 1
fi

if grep -q 'branch .*then block' "$HIR"; then
  echo "dead_nil_branch_after_splat_failed: kept dynamic branch for statically nil exception" >&2
  grep -n 'branch .*then block' "$HIR" >&2 || true
  exit 1
fi

echo "dead_nil_branch_after_splat_ok"
