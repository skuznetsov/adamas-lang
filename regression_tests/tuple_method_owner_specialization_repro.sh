#!/usr/bin/env bash
# Generic Tuple defs are indexed under the template owner (`Tuple#last`).
# Three layers bound every instantiation to that one bare body:
#   * normalize_method_owner_name collapsed `Tuple(...)` to `Tuple`;
#   * lower_member_access (no-paren calls) resolved through the shared
#     template ClassInfo / method-index entry without re-owning;
#   * materialization for callers that seed no pending type-param map
#     (return-type inference) fell back to T=Pointer, so `{{T.size}}` -> 0.
# In stage1 this broke stdlib `Tuple#last` (`rpartition(...).last` in
# `puts "hello"`): `self[-1]` indexed out of the tuple and stage2 crashed.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple_owner_spec.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
HDR='lib LibC
  fun exit(status : Int32) : NoReturn
end'
cat >"$WORK_DIR/np_noparen.cr" <<CR
$HDR
struct Tuple
  def mysize
    {{T.size}}
  end
end
a = {1, 2, 3}
b = {1, 2}
LibC.exit(1) unless a.mysize == 3
LibC.exit(2) unless b.mysize == 2
LibC.exit(3) unless a.mysize() == 3
LibC.exit(4) unless b.mysize() == 2
LibC.exit(0)
CR
cat >"$WORK_DIR/np_begin.cr" <<CR
$HDR
struct Tuple
  def mysz
    {% begin %} {{T.size}} {% end %}
  end
  def last
    {% begin %} self[{{T.size - 1}}] {% end %}
  end
end
def mk(a : Int32, b : Int32, c : Int32)
  {a, b, c}
end
t = {1, 2, 7}
LibC.exit(1) unless t.mysz == 3
LibC.exit(2) unless t.last == 7
u = mk(4, 5, 9)
LibC.exit(3) unless u.last == 9
LibC.exit(4) unless {1, 2}.mysz == 2
LibC.exit(0)
CR
cat >"$WORK_DIR/pl.cr" <<'CR'
t = {"a", "bb", "ccc"}
exit 1 unless t.last == "ccc"
u = {1, "x"}
exit 2 unless u.last == "x"
exit 3 unless "a/b/c".rpartition('/').last == "c"
puts "hello"
exit 0
CR
for name in np_noparen np_begin pl; do
  flags=()
  [[ "$name" == np_* ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1; then
    echo "case $name failed:" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo tuple_method_owner_specialization_repro_ok
