#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_optional_type_param_join.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

if grep -Fq 'template.type_params.map { |param| @type_param_map[param]? }' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  echo "type-ref specialization must not join Array(String?) from @type_param_map" >&2
  exit 1
fi

if grep -Fq 'template.type_params.map { |param| param_map[param]? }' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  echo "function-param specialization must not join Array(String?) from param_map" >&2
  exit 1
fi

if ! grep -Fq 'complete_type_param_mapping(template.type_params, @type_param_map)' "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"; then
  echo "type-ref specialization must build a concrete Array(String) before join" >&2
  exit 1
fi

cat >"$tmpdir/repro.cr" <<'CR'
class Outer(T)
  class Inner(U)
  end

  def take_inner(value : Inner(T)) : Nil
  end
end

class Use
  def self.run(value : Outer(Int32)::Inner(Int32)) : Nil
  end
end
CR

log="$tmpdir/repro.log"
out="$tmpdir/repro"

"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 30 1024 \
  "$tmpdir/repro.cr" --no-prelude --emit llvm-ir --no-link -o "$out" \
  >"$log" 2>&1

if [[ ! -s "$out.ll" ]]; then
  echo "optional type-param join guard did not emit LLVM IR" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

if grep -Eq 'Array\$LString\$Q\$R\$Hjoin|Pointer\$LVoid\$R\$Hto_s|__vdispatch__Object.*to_s|Segmentation fault|Bus error|EXC_BAD_ACCESS|\[CRASH\]|\[KILL\] Timeout' "$log"; then
  echo "optional type-param join guard hit the nilable join crash family" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

echo "p2_optional_type_param_join_no_prelude_ok"
