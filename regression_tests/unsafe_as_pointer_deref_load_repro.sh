#!/usr/bin/env bash
# Regression test for the emit_load "packed-scalar shortcut" miscompile.
#
# Root cause (llvm_backend.cr emit_load): a value cast to a pointer via
# `inttoptr` is tagged in @inttoptr_value_ids. The packed-scalar shortcut then
# loaded such a pointer with `ptrtoint ptr X to <inttype>` (recovering the
# ADDRESS bits) instead of `load <inttype>, ptr X` (dereferencing). This is
# correct for genuine packed scalars (sprintf/file_open/channel), but WRONG for
# a real `Pointer(T)` produced by `addr.unsafe_as(Pointer(T))`, which also
# lowers to inttoptr but must be dereferenced. Result: `.value` returned the
# address instead of the pointed-to value.
#
# This was the root of the non-deterministic s2b startup crash family: the
# String-corruption guard `v2_string_object_header?` probes memory via
# `unsafe_as(Pointer(Int32)).value` and was silently miscompiled into a no-op
# (compared the global's address to 16, never the loaded type_id), so every
# raw-memory introspection site in self-hosted code returned garbage.
# See memory: s2b-startup-crash-rc-overfree-refuted.
#
# Fix: in emit_load, skip the ptrtoint shortcut when the pointer operand has a
# concrete `Pointer(T)` MIR type (non-void element_type) — a genuine address.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/unsafe_as_deref.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
# A genuine Pointer(Int32) reached via inttoptr (unsafe_as) must be loaded.
x = 12345
addr = pointerof(x).as(Void*).address

# Chained form: addr.unsafe_as(Pointer(Int32)).value
chained = addr.unsafe_as(Pointer(Int32)).value
STDERR.puts(chained == 12345 ? "chained_ok" : "chained_bad:#{chained}")

# Split form: separate local for the cast pointer, then .value
p = addr.unsafe_as(Pointer(Int32))
split = p.value
STDERR.puts(split == 12345 ? "split_ok" : "split_bad:#{split}")
STDOUT.flush
STDERR.flush
CR

set +e
"$COMPILER" "$SRC" -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr ---"
  cat "$COMPILE_ERR"
  echo "--- stdout ---"
  cat "$COMPILE_OUT"
  exit 2
fi

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT" 2>&1
# The oracle channel is STDERR (V2 can drop the final STDOUT write on exit).
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

if echo "$stderr_text" | grep -q "chained_ok" && echo "$stderr_text" | grep -q "split_ok"; then
  echo "fixed: genuine Pointer(T) via unsafe_as is dereferenced (load), not ptrtoint"
  exit 0
fi

echo "FAIL: deref returned address bits instead of pointed-to value (emit_load ptrtoint shortcut)"
cat "$RUN_OUT"
exit 1
