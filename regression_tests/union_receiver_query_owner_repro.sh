#!/usr/bin/env bash
# `eff[idx]?` on a `Nil | Array(S)` receiver: resolve_union_method_call's
# generic-stripped fallback returned the bare template target `Array#[]?`,
# which lower_call later re-resolved against another existing instantiation
# (`Array(Z)#[]?$Int32`, present because of `zs[0]?`). The union dispatch then
# typed the call `Nil | Z` and the `||` merge read an S as a Z -> segfault.
# The fallback must stay bound to the candidate owner (`Array(S)#[]?`).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_receiver_query_owner_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
struct S
  VOID = S.new(0)
  def initialize(@v : Int32); end
  def v; @v; end
  def ==(o : S); @v == o.v; end
end

struct Z
  def initialize(@a : Int32); end
  def a; @a; end
end

def expand(ts : Array(S)?) : Array(S)?
  return ts unless ts
  ts
end

def each_i(n, &)
  i = 0
  while i < n
    yield i
    i += 1
  end
end

zs = [Z.new(7)]
if z = zs[0]?
  STDERR.puts z.a
end
eff = expand([S.new(1), S.new(2)])
cnt = 0
each_i(3) do |idx|
  t = eff[idx]? || S::VOID
  cnt += 1 if t != S::VOID
end
STDERR.puts "cnt=#{cnt}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
7
cnt=2
OUT
grep -E '^(7|cnt=[0-9]+)$' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  cat "$WORK_DIR/run.log" >&2
  echo "FAIL: union receiver query bound to a foreign instantiation" >&2
  exit 1
fi
echo "PASS: union receiver query stays on the candidate owner"
