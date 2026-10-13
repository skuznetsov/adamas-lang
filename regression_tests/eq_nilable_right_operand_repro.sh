#!/usr/bin/env bash
# `T == T?` / `T != T?` with a scalar or String left operand and a nilable right
# operand was lowered by the primitive table as a raw compare (String: pointer
# identity), so `scope != @cache_scope` was always true. In S2 this cleared the
# infer-local-type cache on every call and drove exponential lower_call recursion.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/eq_nilable_right.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
class Zc
  @s : String?
  @n : Int32?
  @k : Char?

  def initialize(nilit : Bool)
    @s = nilit ? nil : "a#{1}"
    @n = nilit ? nil : 7
    @k = nilit ? nil : 'q'
  end

  def run(tag)
    a = "a#{1}"
    STDERR.puts "#{tag} s: eq=#{a == @s} ne=#{a != @s} neb=#{"b" != @s} eqb=#{"b" == @s}"
    STDERR.puts "#{tag} n: eq=#{7 == @n} ne=#{7 != @n} ne8=#{8 != @n} eq8=#{8 == @n} i64=#{7_i64 == @n}"
    STDERR.puts "#{tag} k: eq=#{'q' == @k} ne=#{'q' != @k} ner=#{'r' != @k}"
  end
end

Zc.new(false).run("V")
Zc.new(true).run("N")
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
V s: eq=true ne=false neb=true eqb=false
V n: eq=true ne=false ne8=true eq8=false i64=true
V k: eq=true ne=false ner=true
N s: eq=false ne=true neb=true eqb=false
N n: eq=false ne=true ne8=true eq8=false i64=false
N k: eq=false ne=true ner=true
OUT
grep -E '^[VN] [snk]:' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: nilable right operand equality" >&2
  exit 1
fi
echo "PASS: T ==/!= T? compares by value and treats nil as unequal"
