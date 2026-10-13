#!/usr/bin/env bash
# `String | Pointer(Void)` has no primitive member, but MIR stores it as a
# tagged union (raw Pointer arm next to a header-backed arm). HIR skipped
# per-variant dispatch for it ("all class-like"), so the fallback union
# vdispatch returned Int32 and ran generic Object#hash on the raw pointer:
# x.hash differed from the direct String/Pointer hash.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_hash_string_pointer.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/sp.cr" <<'CR'
r = 0
x = ARGV.size == 0 ? "a" : Pointer(Void).null
y = ARGV.size == 0 ? Pointer(Void).null : "a"
r |= 1 unless x.hash == "a".hash
r |= 2 unless y.hash == Pointer(Void).null.hash
r |= 4 unless x.hash.is_a?(UInt64)
r |= 8 unless y.hash.is_a?(UInt64)
STDERR.puts "r=#{r}"
exit(r == 0 ? 3 : 1)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/sp.cr" -o "$WORK_DIR/sp" >"$WORK_DIR/sp.build.log" 2>&1; then
  cat "$WORK_DIR/sp.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/sp" 5 512 >"$WORK_DIR/sp.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/sp.run.log"; then
  echo "sp: want EXIT 3" >&2
  cat "$WORK_DIR/sp.run.log" >&2
  exit 1
fi
echo union_hash_string_pointer_tagged_repro_ok
