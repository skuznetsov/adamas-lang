#!/usr/bin/env bash
# `{m, x}.max` return type inferred as the bare generic `T`: Tuple(*T) has one
# variadic template param, so resolve_return_type_from_def's arity check never
# bound T for Tuple(Int32, Int32) receivers. Loop-phi widening then unioned
# Int32 | T and the tuple was lowered as garbage (S2->S3 crashed in
# register_union_descriptor on `max_size = {max_size, vsize}.max`).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple_enumerable_return_type_param_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
def w(xs : Array(Int32)) : Int32
  m = 0
  i = 0
  while i < xs.size
    m = {m, xs[i]}.max
    i += 1
  end
  m
end

def b(xs : Array(Int32)) : Int32
  m = 100
  xs.each do |x|
    m = {m, x}.min
  end
  m
end

def s(xs : Array(String)) : String
  m = ""
  xs.each { |x| m = {m, x}.max }
  m
end

STDERR.puts "w #{w([1, 20, 3])}"
STDERR.puts "b #{b([7, 2, 9])}"
STDERR.puts "s #{s(["b", "d", "a"])}"
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
printf 'w 20\nb 2\ns d\n' >"$WORK_DIR/expected"
grep -E '^[wbs] ' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: Tuple#max/min return type did not bind T to the element union" >&2
  exit 1
fi
echo "PASS: Tuple#max/min return type binds T to the element union"
