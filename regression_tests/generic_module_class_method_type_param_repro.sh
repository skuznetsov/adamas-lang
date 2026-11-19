#!/usr/bin/env bash
# Regression: class methods of a generic module bind its type parameters.
#
# `Gen(Float64).kind` for `module Gen(T); def self.kind; T; end; end` failed
# with "undefined constant T": monomorphize_generic_module looked the
# template up as @module_defs["Gen"], but the template is keyed by its
# declaration (`Gen(T)`), and its callers guarded on the same bare key, so
# no generic module instance ever had its class methods specialized. The
# specialized registration also has to record a type-literal return, or a
# body returning `T` reaches the call site as an instance (printed "0.0").
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-module-class-method.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
module Gen(T)
  def self.kind
    T
  end

  def self.width
    sizeof(T)
  end

  def self.wrap(x : T) : Array(T)
    [x]
  end

  def self.label
    "gen of #{T}"
  end
end

module Outer
  module GM(A, B)
    def self.names
      "#{A}-#{B}"
    end

    def self.first
      A
    end
  end
end

STDERR.puts Gen(Float64).kind
x = Gen(Float64).kind
STDERR.puts x.name
STDERR.puts Gen(Char).kind
STDERR.puts Gen(Int64).width
STDERR.puts Gen(UInt8).width
STDERR.puts Gen(Int32).wrap(5).inspect
STDERR.puts Gen(Int32).label
STDERR.puts Outer::GM(Int32, Bool).names
STDERR.puts Outer::GM(Char, Bool).first
STDERR.puts Gen(Array(Int32)).kind
CR

expected='Float64
Float64
Char
8
1
[5]
gen of Int32
Int32-Bool
Char
Array(Int32)'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH' || true; }

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

echo "PASS: generic module class methods bind their type parameters"
