#!/usr/bin/env bash
# RED oracle (open bug, PRE-EXISTING — reproduced on June-21 bin/adamas_fix
# and 2026-07-04 pre-8cab1d05 binaries alike): `Path#each_parent { }` is
# miscompiled by stage1.
#
#   Path["/a/b/c/d"].each_parent { |p| puts p }
#
# Host prints "/", "/a", "/a/b", "/a/b/c". V2-compiled binary prints a single
# wrong "/a/" and dies with SIGTRAP (brk #0x1) inside
# Path.next_part_separator_index$$Char::Reader_Bool_Tuple(Char)|Tuple(Char,Char).
#
# Suspected family (see TODO 2026-07-04 late night): non-local `return
# reader, true, start_pos` of a TUPLE from inside the inlined
# `Char::Reader#each` yield block, with `next` in the same block and return
# type Nil | Tuple(Char::Reader, Bool, Int32) — the "$block raw-return
# without union_wrap" + "inline-yield + next" open tails. The `separators`
# param is itself a union of tuple types (Tuple(Char) | Tuple(Char, Char)).
#
# This is the s2_v11 parallel-emission killer: LLVMIRGenerator#
# emit_functions_parallel -> Dir.mkdir_p -> Path#each_parent -> brk.
#
# Green when: output matches host lines and exit is 0.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/path_each_parent.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
cat > "$SRC" <<'CR'
Path["/a/b/c/d"].each_parent { |p| puts p }
CR

if ! "$COMPILER" "$SRC" -o "$OUT" > "$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -5 "$TMP_DIR/compile.log" >&2
  exit 1
fi

RAW="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null)"
GOT="$(echo "$RAW" | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED=$'/\n/a\n/a/b\n/a/b/c'

if [[ "$GOT" != "$EXPECTED" ]]; then
  echo "FAIL: each_parent output mismatch" >&2
  echo "--- expected ---" >&2
  echo "$EXPECTED" >&2
  echo "--- got ---" >&2
  echo "$GOT" >&2
  exit 1
fi
if ! echo "$RAW" | grep -q "\[EXIT: 0\]"; then
  echo "FAIL: non-zero exit (SIGTRAP brk in next_part_separator_index?)" >&2
  echo "$RAW" | tail -2 >&2
  exit 1
fi
echo "PASS: Path#each_parent yields all parents and exits cleanly"
