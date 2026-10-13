#!/usr/bin/env bash
# Regression: a bare constant macro argument (`rec St`) was bound through the
# Path -> TypeNode resolver, so inside `module M` the name `St` resolved to the
# lib struct `LibX::St` and `struct {{name.id}}` declared `M::LibX::St` (plus a
# phantom `M::LibX` module). Stdlib `record ProfStats` in `module GC` thereby
# produced `GC::LibGC`, and `LibGC.init` emitted a duplicate `GC_init`.
# Macro arguments are unevaluated AST nodes in Crystal: `.id` must give `St`.
# Must print EXIT 7 and the HIR must declare `M::St`, never `M::LibX::St`.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_arg_path_unresolved.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/m.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

lib LibX
  struct St
    a : Int32
  end
end

macro rec(name)
  struct {{name.id}}
    def v : Int32
      {{ name.id.stringify.size }} + 5
    end
  end
end

module M
  rec St
end

LibC.exit(M::St.new.v)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/m.cr" --no-prelude -o "$WORK_DIR/m" --emit hir >"$WORK_DIR/build.log" 2>&1; then
  echo "compile failed" >&2
  tail -20 "$WORK_DIR/build.log" >&2
  exit 1
fi
if grep -q 'M::LibX' "$WORK_DIR/m.hir"; then
  echo "phantom M::LibX type declared:" >&2
  grep 'M::LibX' "$WORK_DIR/m.hir" | head -5 >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/m" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 7\]' "$WORK_DIR/run.log"; then
  echo "want EXIT 7:" >&2
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo macro_arg_path_unresolved_repro_ok
