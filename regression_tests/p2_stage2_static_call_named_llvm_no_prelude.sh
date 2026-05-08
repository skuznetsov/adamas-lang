#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_static_call_named_llvm.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/repro.cr" <<'CR'
class Exception
  class CallStack
    def self.skip(path : String) : Nil
    end
  end
end

Exception::CallStack.skip("x")
CR

log="$tmpdir/repro.log"
out_base="$tmpdir/repro"
ir="$tmpdir/repro.ll"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 60 2048 \
  "$tmpdir/repro.cr" --no-prelude --emit llvm-ir --no-link -o "$out_base" \
  >"$log" 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "static-call LLVM oracle failed to emit IR" >&2
  tail -n 120 "$log" >&2 || true
  exit 1
fi

if [[ ! -f "$ir" ]]; then
  awk '
    /^=== STDOUT ===$/ {capture=1; next}
    /^=== STDERR ===$/ {capture=0}
    capture {print}
  ' "$log" >"$ir"
fi

if [[ ! -s "$ir" ]]; then
  echo "static-call LLVM oracle produced no IR" >&2
  tail -n 120 "$log" >&2 || true
  exit 1
fi

if grep -Fq '@func1' "$ir"; then
  echo "static call lowered to fallback @func1 instead of the named callee" >&2
  grep -Fn '@func1' "$ir" >&2 || true
  exit 1
fi

if grep -Fq 'call  @' "$ir"; then
  echo "static call emitted an empty LLVM return type" >&2
  grep -Fn 'call  @' "$ir" >&2 || true
  exit 1
fi

grep -Fq 'call void @Exception$CCCallStack$Dskip$$String(ptr @.str.0)' "$ir"
grep -Fq 'define void @Exception$CCCallStack$Dskip$$String' "$ir"

if command -v llc >/dev/null 2>&1; then
  llc -filetype=obj -o "$tmpdir/repro.o" "$ir"
fi

echo "p2_stage2_static_call_named_llvm_no_prelude_ok"
