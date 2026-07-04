#!/usr/bin/env bash
# Regression: wrapping a non-POD struct into a union must COPY the struct,
# not alias its source storage.
#
# Root cause of the flaky s2 HIR segfault (2026-07-04, "NULL ClassNode#body in
# register_concrete_class <- monomorphize_generic_class(Channel(Int32))"):
# `existing = @generic_templates[class_name]?` compiles to Hash#[]? whose
# return union payload held an INTERIOR POINTER into the hash's entries
# buffer. The record pushed into @generic_reopenings therefore aliased the
# live entry slot: `@generic_templates[k] = new_template` rewrote it in
# place, and a later entries realloc left the reopenings array holding a
# dangling pointer into freed (reused, zeroed) memory -> null ClassNode.
# ASLR decided what landed in the freed slot, hence the flake.
#
# Fix: llvm_backend emit_union_wrap clones struct-kind variant payloads into
# a fresh heap cell ($Dnew shape: 8-byte immortal RC header + fields) before
# storing the payload pointer. POD/inline-copy reprs were already correct.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_struct_alias.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
class NodeA
  getter x : Int32
  def initialize(@x); end
end
class ArenaX; end
class ArenaY; end

# Shaped like HIR::GenericClassTemplate: reference fields + union field, so
# the record is NOT recursively-POD and uses the pointer repr.
record T3,
  name : String,
  params : Array(String),
  node : NodeA,
  arena : ArenaX | ArenaY,
  flag : Bool = false

h = {} of String => T3
h["k"] = T3.new("chan", ["T"], NodeA.new(111), ArenaX.new)
old = h["k"]?                                   # union Nil | T3 lookup
h["k"] = T3.new("chan2", ["U"], NodeA.new(222), ArenaY.new)
if o = old
  puts o.node.x   # host: 111 (copy); aliasing bug printed 222
  puts o.name     # host: chan; aliasing bug printed chan2
end

# POD sibling (recursively-POD record) — was already correct, must stay so.
record P2, a : Int32, b : Int32
hp = {} of String => P2
hp["k"] = P2.new(1, 2)
oldp = hp["k"]?
hp["k"] = P2.new(3, 4)
if op = oldp
  puts op.a       # host: 1
end
CR

if ! "$COMPILER" "$SRC" -o "$OUT" > "$LOG" 2>&1; then
  echo "FAIL: compile error"
  tail -5 "$LOG"
  exit 1
fi

ACTUAL="$("$RUN_SAFE" "$OUT" 10 512 | awk '/^=== STDOUT ===$/{f=1;next} /^=== STDERR ===$/{f=0} f')"
EXPECTED=$'111\nchan\n1'

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  echo "PASS: union-wrapped struct is an independent copy (111/chan/1)"
else
  echo "FAIL: expected [111 chan 1], got:"
  echo "$ACTUAL"
  exit 1
fi
