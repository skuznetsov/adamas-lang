#!/usr/bin/env bash
# Call-site named args packed into a `**opts` slot must be allocated with the
# concrete NamedTuple(k: T, ...) layout. The bare generic NamedTuple lowers to
# `type {}` (0 bytes), so the packed payload stores overflowed the slot.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/double_splat_named_tuple.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/nta.cr" <<'CR'
def tr2(op : String, **metadata)
  metadata
end

def f(n : UInt64)
  tr2 "m", size: n, atomic: 3
end

f(5_u64)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/nta.cr" -o "$WORK_DIR/nta" --emit llvm-ir >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

LL="$WORK_DIR/nta.ll"
[ -f "$LL" ] || LL="$WORK_DIR/nta.ll.ll"
body="$(awk '/^define.*@"?f\$\$UInt64/,/^}/' "$LL")"
if [ -z "$body" ]; then
  echo "FAIL: f\$\$UInt64 not found in IR" >&2
  exit 1
fi
if grep -q 'alloca %NamedTuple,' <<<"$body"; then
  echo "FAIL: packed named args allocated as bare (0-byte) NamedTuple" >&2
  grep alloca <<<"$body" >&2
  exit 1
fi
# The packed NamedTuple is returned, so it must not live in f's frame at all
# (see call_result_arg_alias_escape_repro.sh); a stack slot here is a
# use-after-return regardless of its size.
if grep -q 'alloca \[16 x i8\]' <<<"$body"; then
  echo "FAIL: returned packed NamedTuple allocated in a stack slot" >&2
  grep alloca <<<"$body" >&2
  exit 1
fi
echo double_splat_named_tuple_layout_repro_ok
