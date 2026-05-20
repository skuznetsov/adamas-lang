#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_type_param_like_cacheless.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

if grep -Fq '@type_param_like_cache' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  echo "type_param_like? must not use a Hash(String, Bool) cache on the stage2 registration frontier" >&2
  exit 1
fi

cat >"$tmpdir/repro.cr" <<'CR'
module SourceLike
  def token_value(x : T) : T
    x
  end

  def map_pair(x : Array(T), y : U, &block : U -> T) : Nil
  end
end

class Sink
  include SourceLike
end
CR

log="$tmpdir/repro.log"
out="$tmpdir/repro"

"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 30 1024 \
  "$tmpdir/repro.cr" --no-prelude --emit llvm-ir --no-link -o "$out" \
  >"$log" 2>&1

if [[ ! -s "$out.ll" ]]; then
  echo "type_param_like cacheless guard did not emit LLVM IR" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

if grep -Eq 'Hash\(String, Bool\)#key_hash|type_param_like\?|Segmentation fault|Bus error|EXC_BAD_ACCESS|\[CRASH\]|\[KILL\] Timeout' "$log"; then
  echo "type_param_like cacheless guard hit the registration-cache crash family" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

echo "p2_type_param_like_cacheless_no_prelude_ok"
