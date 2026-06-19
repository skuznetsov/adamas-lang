#!/usr/bin/env bash
# Regression test: a struct-typed instance var whose default is an unresolvable
# module/type constant must not crash under the step-4 small-struct inline ABI
# (ADAMAS_INLINE_SMALL_STRUCTS=1).
#
# Bug (latent until step-4 exposed it): in generate_allocator, a struct-typed
# ivar default that is NOT a simple numeric constant (e.g. `Index.new(-1, 0)`
# behind a constant) was lowered with the plain expression path, which degraded
# to a scalar `literal 0 : Int32` register. The legacy pointer-carrier ABI
# tolerated this (the slot is an 8-byte pointer; the scalar lands as a null
# pointer). The step-4 inline-struct store, however, `memcpy`s the value bytes
# FROM the default as if it were an address -> SIGSEGV at startup, because the
# stdlib hits this on `IO::FileDescriptor#@volatile_fd : Atomic(Handle)` /
# `@__evloop_data : Arena::Index = INVALID_INDEX` before `main` even runs.
#
# Fix (ast_to_hir.cr generate_allocator, both allocator generators): when the
# ivar is struct-typed and the lowered default is NOT itself a struct value,
# route it to a zero-struct Allocate (matching the no-default struct path).
# The declared default is still lost (separate, documented "Default ivar values
# from modules: Not yet implemented" bug) but the inline store now has a valid
# memory source instead of a scalar register, so it no longer crashes.
#
# Guards two things:
#   A) full-prelude hello-world compiles + runs clean gate-ON (the exact
#      IO::FileDescriptor startup SIGSEGV that blocked the flip).
#   B) a user struct-typed ivar with a struct-constant default that lower_expr
#      CAN build keeps its real default gate-ON (the fix's zero-fallback is
#      conditional, so it must not clobber a correctly-lowered struct default).
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/struct_ivar_default.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail=0

# Compile + run a source under ADAMAS_INLINE_SMALL_STRUCTS=1 and assert the
# program does NOT crash (exit code 0). $expect (optional) also matches stdout.
run_gate_on() {
  local name="$1" src="$2" expect="${3:-}"
  local cr="$TMP_DIR/$name.cr" bin="$TMP_DIR/$name.bin" out="$TMP_DIR/$name.out"
  printf '%s' "$src" >"$cr"
  if ! ADAMAS_INLINE_SMALL_STRUCTS=1 "$COMPILER" "$cr" -o "$bin" \
        >"$TMP_DIR/$name.compile" 2>&1; then
    echo "FAIL[$name]: compile error (gate-ON)"; cat "$TMP_DIR/$name.compile"; fail=1; return
  fi
  set +e
  "$bin" >"$out" 2>/dev/null
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "FAIL[$name]: runtime crash gate-ON (exit $rc)"; fail=1; return
  fi
  local got; got="$(cat "$out")"
  if [[ -n "$expect" && "$got" != "$expect" ]]; then
    echo "FAIL[$name]: expected [$expect] got [$got]"; fail=1; return
  fi
  echo "PASS[$name]: exit 0${got:+ [$got]}"
}

# Case A: full-prelude hello-world must boot gate-ON. The stdlib's struct-typed
# ivars with constant defaults run during IO/EventLoop setup before main.
run_gate_on hello_prelude 'puts "hi"' "hi"

# Case B: user struct-typed ivar defaulting to a struct constant that lower_expr
# CAN build (a plain top-level constant). Here the lowered default IS a struct, so
# the fix's guard must NOT fire the zero-fallback and the real default (-1) must
# survive. This guards that the fix is conditional (zero-fallback only on genuine
# degradation) — a naive "always zero struct defaults" fix would print 0.
run_gate_on user_struct_const_default 'struct Idx
  @data : Int64
  def initialize(@data : Int64)
  end
  def data : Int64
    @data
  end
end

INVALID = Idx.new(-1_i64)

class Holder
  @idx : Idx = INVALID
  def idx : Idx
    @idx
  end
end

h = Holder.new
# lower_expr builds the struct here, so the declared default (-1) is preserved.
puts h.idx.data' "-1"

if [[ $fail -ne 0 ]]; then
  echo "RESULT: FAIL"; exit 1
fi
echo "RESULT: PASS"
