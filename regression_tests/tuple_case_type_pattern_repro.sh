#!/usr/bin/env bash
# `case {left, right} when {Int64, Int64}` is `Int64 === left && Int64 ===
# right` in original Crystal: a type element tests the subject element's type
# and narrows a local element inside the branch. V2 compared each element with
# `==` against the type literal (never true, every value fell to `else`) and
# narrowed nothing, so stage 2 failed in MIR::ConstantFoldingPass#fold_binary
# with "no overload matches fold_int_op (BinOp, Nil | Bool | ..., ...)".
# A member name that also names a type (`Kind::Bool` vs `Bool`) is the member
# only inside the enum; elsewhere `when Bool` is the type `::Bool`.
# Expected output is checked against original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple-case-type-pattern.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/t.cr" <<'CR'
def fi(a : Int64, b : Int64) : Int64
  a + b
end

def fb(a : Bool, b : Bool) : Bool
  a && b
end

def fold(left, right) : (Int64 | Bool)?
  case {left, right}
  when {Int64, Int64}
    fi(left, right)
  when {Bool, Bool}
    fb(left, right)
  else
    nil
  end
end

def kind(left, right) : String
  case {left, right}
  when {Int64, Int64} then "ii"
  when {Bool, Bool}   then "bb"
  when {Int64, Bool}  then "ib"
  else                     "other"
  end
end

enum Op
  Add
  Neg
end

def op_kind(op : Op, v) : String
  case {op, v}
  when {Op::Add, Int64} then "add-i"
  when {Op::Neg, Int64} then "neg-i"
  when {Op::Add, 1.5}   then "add-1.5"
  else                       "other"
  end
end

enum Kind
  Bool
  Other

  def self_bool? : ::Bool
    case self
    when Bool then true
    else           false
    end
  end
end

def kind_pair(k : Kind, n) : String
  case {k, n}
  when {Bool, Int32} then "type-bool"
  else                    "other"
  end
end

def kind_bare(k : Kind) : String
  case k
  when Bool then "type-bool"
  else           "other"
  end
end

def get(k : Int32) : Int64 | Bool | Float64 | Nil
  case k
  when 0 then 3_i64
  when 1 then true
  when 2 then 1.5
  else        nil
  end
end

STDERR.puts fold(get(0), get(0)).inspect
STDERR.puts fold(get(1), get(1)).inspect
STDERR.puts fold(get(0), get(1)).inspect
STDERR.puts fold(get(2), get(3)).inspect
STDERR.puts kind(get(0), get(0))
STDERR.puts kind(get(1), get(1))
STDERR.puts kind(get(0), get(1))
STDERR.puts kind(get(2), get(3))
STDERR.puts kind(1_i64, 2_i64)
STDERR.puts kind(1_i64, "x")
STDERR.puts op_kind(Op::Add, get(0))
STDERR.puts op_kind(Op::Neg, get(0))
STDERR.puts op_kind(Op::Add, get(2))
STDERR.puts op_kind(Op::Neg, get(1))
STDERR.puts kind_pair(Kind::Bool, 1)
STDERR.puts kind_bare(Kind::Bool)
STDERR.puts Kind::Bool.self_bool?
STDERR.puts Kind::Other.self_bool?
CR

printf '%s\n' 6 true nil nil ii bb ib other ii other add-i neg-i add-1.5 other \
  other other true false > "$WORK_DIR/want"

stderr_of() {
  awk '/^=== STDERR ===$/ { on = 1; next } /^\[EXIT: / { on = 0 } on' "$1"
}

if [[ -n "$CRYSTAL_BIN" ]]; then
  if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build "$WORK_DIR/t.cr" \
      -o "$WORK_DIR/t.orig" > "$WORK_DIR/orig.log" 2>&1; then
    printf 'ORACLE FAIL: original rejects the program\n' >&2
    cat "$WORK_DIR/orig.log" >&2
    exit 2
  fi
  "$SAFE_RUNNER" "$WORK_DIR/t.orig" 5 256 > "$WORK_DIR/orig.run" 2>&1 || true
  if ! stderr_of "$WORK_DIR/orig.run" | diff -u "$WORK_DIR/want" - >&2; then
    printf 'ORACLE FAIL: original output differs\n' >&2
    exit 2
  fi
fi

"$SAFE_RUNNER" "$ADAMAS_BIN" 600 8192 "$WORK_DIR/t.cr" -o "$WORK_DIR/t.adamas" \
  > "$WORK_DIR/adamas.log" 2>&1 || true
if [[ ! -x "$WORK_DIR/t.adamas" ]]; then
  printf 'FAIL: compile failed\n' >&2
  grep -m3 -a 'rror' "$WORK_DIR/adamas.log" >&2 || tail -5 "$WORK_DIR/adamas.log" >&2
  exit 1
fi
"$SAFE_RUNNER" "$WORK_DIR/t.adamas" 5 256 > "$WORK_DIR/adamas.run" 2>&1 || true
if ! stderr_of "$WORK_DIR/adamas.run" | diff -u "$WORK_DIR/want" - >&2; then
  printf 'FAIL: output differs from original Crystal\n' >&2
  exit 1
fi
printf 'PASS tuple case type patterns\n'
