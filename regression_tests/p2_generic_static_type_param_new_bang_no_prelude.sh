#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_generic_static_new_bang.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Direct(T, U)
  def self.f(x : UInt64)
    U.new!(x)
  end
end

module Included(T, EquivUint)
  def g(x : UInt64)
    EquivUint.new!(x)
  end
end

struct Box
  include Included(Int32, UInt64)
end

a = Direct(Int32, UInt64).f(7_u64)
b = Box.new.g(9_u64)
LibC.exit((a == 7_u64 && b == 9_u64) ? 0 : 1)
CR

log="$tmpdir/repro.log"
out="$tmpdir/repro"

"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 60 2048 \
  "$tmpdir/repro.cr" --no-prelude --emit llvm-ir --no-link -o "$out" \
  >"$log" 2>&1

if [[ ! -s "$out.ll" ]]; then
  echo "generic static type-param guard did not emit LLVM IR" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

if grep -Eq '(@|STUB CALLED: )(U|EquivUint)\$Dnew\$BANG' "$out.ll"; then
  echo "generic static type-param guard found unresolved type-param new! owner" >&2
  grep -n -E '(U|EquivUint)\$Dnew\$BANG' "$out.ll" >&2 || true
  exit 1
fi

if grep -Eq 'define void @Direct\$LInt32\$C\$_UInt64\$R\$Df\$\$UInt64|define void @Box\$Hg\$\$UInt64' "$out.ll"; then
  echo "generic static type-param guard found void-returning lowered method" >&2
  grep -n -E 'define void @(Direct\$LInt32\$C\$_UInt64\$R\$Df\$\$UInt64|Box\$Hg\$\$UInt64)' "$out.ll" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 60 2048 \
  "$tmpdir/repro.cr" --no-prelude -o "$out" \
  >"$log.bin" 2>&1

"$ROOT_DIR/scripts/run_safe.sh" "$out" 5 512 >"$log.run" 2>&1

echo "p2_generic_static_type_param_new_bang_no_prelude_ok"
