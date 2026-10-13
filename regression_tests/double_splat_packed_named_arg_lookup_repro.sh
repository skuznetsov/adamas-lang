#!/usr/bin/env bash
# Overload lookup over already-lowered args must not count named args that were
# packed into the trailing `**opts` NamedTuple slot as consumed positionals.
# With >= 3 extra named args the positional count went below the required
# arity, the `**` overload was rejected, and the call was mangled with the
# concrete `NamedTuple(k: T, ...)` type (S2: Ambiguous MIR call target).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/double_splat_packed_lookup.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/ntt.cr" <<'CR'
module Mm
  def self.tr(s : Int32, operation : String, t : UInt64? = nil, **md, &)
    yield
  end

  def self.tr(s : Int32, operation : String, t : UInt64? = nil, **md)
  end
end

class K
  def a(i : Int32)
    Mm.tr 1, "u1", op: "add", fd: i
  end

  def b(i : Int32)
    Mm.tr 1, "u2", op: "add", fd: i, index: 7_i64
  end
end

K.new.a(1)
K.new.b(2)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/ntt.cr" --no-prelude -o "$WORK_DIR/ntt" --emit hir >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

HIR="$WORK_DIR/ntt.hir"
# A lookup miss mangles the concrete NamedTuple without the `_double_splat`
# marker. Per-layout `**` specializations keep the marker and are fine.
if grep -E 'call Mm\.tr\$[^(]*_NamedTuple\([^)]*\)' "$HIR" | grep -vqF ')_double_splat('; then
  echo "FAIL: ** call mangled with concrete NamedTuple type (lookup miss)" >&2
  grep -o 'call Mm\.tr\$[^(]*_NamedTuple([^)]*)[^(]*' "$HIR" >&2
  exit 1
fi
count="$(grep -c 'call Mm\.tr\$.*_double_splat(' "$HIR" || true)"
if [ "$count" != "2" ]; then
  echo "FAIL: expected 2 calls to the ** overload, got $count" >&2
  exit 1
fi
for callee in $(grep -o 'call Mm\.tr\$.*_double_splat(' "$HIR" | sed 's/^call //; s/($//' | tr ' ' '~'); do
  name="${callee//\~/ }"
  if ! grep -qF "func @$name(" "$HIR"; then
    echo "FAIL: called ** specialization has no body: $name" >&2
    exit 1
  fi
done
echo "PASS: packed ** named args resolve to the double-splat overload"
