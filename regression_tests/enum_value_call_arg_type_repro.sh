#!/usr/bin/env bash
# `k.value` on an enum returned the enum-tagged receiver value, so the enum
# name leaked into callee mangling (`line$Int32_NK`) instead of the base
# integer type. In the compiler this made `trace_parsed_class_line(...,
# kind.value)` an ambiguous MIR call target during S2->S3.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_value_call_arg_type_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
enum NK
  A
  B
end

def line(a : Int32, c : Int32? = nil) : Nil
  STDERR.puts "#{a} #{c}"
end

line(1)
k = NK::B
line(1, k.value)
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
printf '1 \n1 1\n' >"$WORK_DIR/expected"
grep -E '^1( |$)' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: enum .value passed as Int32 argument" >&2
  exit 1
fi

mkdir -p "$WORK_DIR/ir"
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/ir/t" --emit llvm-ir >"$WORK_DIR/ir.log" 2>&1; then
  cat "$WORK_DIR/ir.log" >&2
  exit 1
fi
if [[ ! -f "$WORK_DIR/ir/t.ll" ]]; then
  echo "FAIL: no LLVM IR emitted" >&2
  exit 1
fi
if grep -nE '@line\$+[^(]*NK\(' "$WORK_DIR/ir/t.ll" >&2; then
  echo "FAIL: enum name leaked into callee mangling via .value" >&2
  exit 1
fi
echo "PASS: enum .value is typed as its base integer"
