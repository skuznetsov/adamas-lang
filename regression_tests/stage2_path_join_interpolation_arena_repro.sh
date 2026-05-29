#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

compiler="$1"
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workdir="$(mktemp -d "${TMPDIR:-/tmp}/stage2_path_join_interpolation_arena.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

src="$workdir/repro.cr"
out_base="$workdir/repro_out"
compile_log="$workdir/compile.log"
hir_file="$out_base.hir"

cat >"$src" <<'CR'
class Demo
  def path_join(a : String, b : String) : String
    if a.ends_with?('/')
      "#{a}#{b}"
    else
      "#{a}/#{b}"
    end
  end

  def path_join(a : String, b : String, c : String) : String
    path_join(path_join(a, b), c)
  end
end

puts Demo.new.path_join("root", "dir")
puts Demo.new.path_join("root", "dir", "leaf")
CR

set +e
(
  cd "$repo_root"
  export ADAMAS_STOP_AFTER_HIR=1
  "$compiler" --emit hir "$src" -o "$out_base"
) >"$compile_log" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "inconclusive: compile failed or timed out with status=$compile_status" >&2
  echo "--- compile log ---" >&2
  cat "$compile_log" >&2
  exit 2
fi

if [[ ! -f "$hir_file" ]]; then
  echo "inconclusive: expected HIR dump $hir_file was not produced" >&2
  echo "--- compile log ---" >&2
  cat "$compile_log" >&2
  exit 2
fi

func_line=$(rg -n 'func @Demo#path_join\$String_String' "$hir_file" | cut -d: -f1 | head -n1)
if [[ -z "$func_line" ]]; then
  echo "inconclusive: Demo#path_join(String, String) was not found in HIR dump" >&2
  exit 2
fi

func_dump="$workdir/path_join.hir"
sed -n "${func_line},$((func_line + 24))p" "$hir_file" >"$func_dump"

if rg -q 'call Thread\.new\(\)|classvar_set Demo\.@@current_thread' "$func_dump"; then
  echo "reproduced: overloaded interpolation path_join still lowers to the wrong body"
  echo "--- offending function ---" >&2
  cat "$func_dump" >&2
  exit 1
fi

if rg -q 'String#ends_with\?\$Char|string_interpolation' "$func_dump"; then
  echo "not reproduced"
  exit 0
fi

echo "inconclusive: Demo#path_join(String, String) did not match either expected HIR signature" >&2
echo "--- function dump ---" >&2
cat "$func_dump" >&2
exit 2
