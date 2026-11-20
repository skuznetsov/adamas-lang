#!/usr/bin/env bash
# Regression: `Type[args]` is the class-method call `Type.[](args)` and must
# lower like the explicit spelling.
#
# The static-owner branch of IndexNode lowering emitted a raw Call to the
# declared family name (`Path.[]$Path | String$arity2_splat`) with the index
# actuals as written. Splat parameters were never packed and the body was
# lowered without the callsite types:
# - `Path["x", "y"]` passed the String "y" where `parts` expects the packed
#   `Tuple(String)`; the body forwarded a null tuple and the program died with
#   SIGILL.
# - `Bag["a", "b", "c"]` over `def self.[](first : String, *rest)` printed
#   `b:1` instead of `a:2`.
# - `Path[["m", "n"]]` (the `parts : Enumerable` overload) failed to compile.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/static-bracket-call.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
class Bag
  def self.[](first : String, *rest) : String
    "#{first}:#{rest.size}"
  end
end

class Pick
  def self.[](x)
    "pick(#{x})"
  end

  def self.[](x, y)
    "pick(#{x},#{y})"
  end
end

STDERR.puts Bag["a", "b", "c"]
STDERR.puts Bag["z"]
STDERR.puts Bag.[]("e", "f")
STDERR.puts Pick[1]
STDERR.puts Pick["s", 2]
STDERR.puts Path["x", "y"].to_s
STDERR.puts Path["solo"].to_s
STDERR.puts Path[["m", "n"]].to_s
STDERR.puts Bytes[1u8, 2u8].size
STDERR.puts StaticArray[1, 2, 3].sum
CR

expected='a:2
z:0
e:1
pick(1)
pick(s,2)
x/y
solo
m/n
2
6'

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

echo "PASS: Type[args] lowers as the class-method call Type.[](args)"
