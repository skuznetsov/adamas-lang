#!/usr/bin/env bash
# A builtin generic spelled with nilable sugar (`Array(String?)`) interns its
# TypeRef under the canonical name `Array(Nil | String)`, but ivar/declared types
# and type-literal receivers (`Array(String?).new`) monomorphized the class under
# the source spelling. One TypeRef then owned two method families
# (`Array(String?)#...` and `Array(Nil | String)#...`) that bound differently; in
# stage2 `@param_default_literals.fetch(i) { nil }` lost every default literal.
# HIR must contain only the canonical owner spelling.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/builtin_generic_nilable_owner_canonical_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/c1.cr" <<'CR'
class Holder
  @lits : Array(String?)
  def initialize
    @lits = [] of String?
  end
  def set(i : Int32, v : String?)
    while @lits.size <= i
      @lits << nil
    end
    @lits[i] = v
  end
  def get(i : Int32) : String?
    @lits.fetch(i) { nil }
  end
end
h = Holder.new
h.set(1, "10")
y = Array(String?).new
y << "b"
STDERR.puts h.get(1).inspect
STDERR.puts h.get(0).inspect
STDERR.puts y.fetch(0) { nil }.inspect
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/c1.cr" --emit hir -o "$WORK_DIR/c1" >"$WORK_DIR/c1.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/c1.build.log" >&2
  exit 1
fi
canonical="$(grep -c '^func @Array(Nil | String)' "$WORK_DIR/c1.hir" || true)"
sugared="$(grep -c '^func @Array(String?)' "$WORK_DIR/c1.hir" || true)"
if [ "$canonical" -eq 0 ]; then
  echo "FAIL: no canonical Array(Nil | String) methods (probe not exercised)" >&2
  exit 1
fi
if [ "$sugared" -ne 0 ]; then
  echo "FAIL: $sugared Array(String?) methods split from the canonical owner" >&2
  grep '^func @Array(String?)' "$WORK_DIR/c1.hir" | head -5 >&2
  exit 1
fi
echo "PASS: builtin nilable generic methods use one canonical owner"
