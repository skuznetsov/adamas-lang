#!/usr/bin/env bash
# Regression: type names shown to the program spell every union the way
# Crystal's UnionType#to_s does, with Nil last, also inside generic arguments.
#
# V2's canonical union name puts Nil first (it keys mangling and registries),
# and every user-visible producer printed that canonical spelling:
# - `typeof(g)` for `g : Int32?` printed `(Nil | Int32)`;
# - `[1, nil].class` printed `Array(Nil | Int32)` (runtime type name table);
# - `Array(Int32?).name` / `.to_s(io)` printed the macro `@type.name` of a
#   ClassSymbol owner verbatim;
# - interpolation, `io << T` and `inspect` of type values did the same.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-display-nil-last.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class Zeta; end
class Alpha; end
c = ARGV.size > 5
a = c ? 1 : 1.5
f = c ? Zeta.new : Alpha.new
g = c ? nil : 1
w = c ? 'a' : (c ? nil : 1.5)
arr = [1, nil]
STDERR.puts typeof(a)
STDERR.puts typeof(f)
STDERR.puts typeof(g)
STDERR.puts typeof(w)
STDERR.puts typeof(c ? nil : [1])
STDERR.puts typeof(c ? nil : {1, nil})
STDERR.puts arr.class
STDERR.puts typeof(arr)
STDERR.puts Array(Int32?).name
STDERR.puts Array(Int32 | Nil)
STDERR.puts({"a" => g}.class)
STDERR.puts({g, 1}.class)
STDERR.puts({a: g, b: "x"}.class)
STDERR.puts "#{typeof(g)}|#{Array(Int32?)}|#{arr.class}"
s = String.build do |io|
  io << typeof(g) << "," << arr.class << "," << Hash(String, Int32?)
end
STDERR.puts s
STDERR.puts typeof(g).inspect
STDERR.puts arr.class.inspect
STDERR.puts arr.class == Array(Int32?)
STDERR.puts typeof(g).name.size
CR

expected='(Float64 | Int32)
(Alpha | Zeta)
(Int32 | Nil)
(Char | Float64 | Nil)
(Array(Int32) | Nil)
(Tuple(Int32, Nil) | Nil)
Array(Int32 | Nil)
Array(Int32 | Nil)
Array(Int32 | Nil)
Array(Int32 | Nil)
Hash(String, Int32 | Nil)
Tuple(Int32 | Nil, Int32)
NamedTuple(a: Int32 | Nil, b: String)
(Int32 | Nil)|Array(Int32 | Nil)|Array(Int32 | Nil)
(Int32 | Nil),Array(Int32 | Nil),Hash(String, Int32 | Nil)
(Int32 | Nil)
Array(Int32 | Nil)
true
13'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH\|run_safe\.sh: ' || true; }

run_program() {
  local bin="$1"
  set +e
  out="$("$SAFE_RUNNER" "$bin" 5 256 2>&1)"
  status=$?
  set -e
  printed="$(printf '%s\n' "$out" | strip)"
}

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  run_program "$WORK_DIR/m_oracle"
  if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: exit=$status" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

run_program "$WORK_DIR/m"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: user-visible union names put Nil last"
