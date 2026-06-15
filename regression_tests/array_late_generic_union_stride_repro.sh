#!/usr/bin/env bash
# Regression: late-generic Array(T)#<< / #unsafe_fetch template buffer stride.
#
# emit_dead_code_stub synthesizes the bodies of Array(T)#<<, #push and
# #unsafe_fetch for generic instantiations that RTA references but never lowers
# through the normal HIR->MIR path ("late generic" dead-code stubs). The buggy
# template indexed the element buffer with a TYPED gep:
#
#     %slot = getelementptr <elem_type>, ptr %buf, i64 %idx64   ; store
#     %value = getelementptr <elem_type>, ptr %buf, i64 %index  ; unsafe_fetch
#
# while the grow/realloc path multiplied the capacity by a hardcoded 16 for any
# `.union` element (llvm_store_size_bytes). For a union whose LLVM type is
# `{i32, [4 x i32]}` (e.g. Dir::Globber's PatternType, sizeof 20, MIR stride 24)
# the three oracles disagreed: realloc grew by 16, the store wrote at LLVM-sizeof
# 20, and the literal alloc / read used the MIR stride. The buffer was too small
# and Array#<< wrote out of bounds -> heap corruption inside Dir::Globber and a
# non-deterministic segfault during stage2 self-compile.
#
# The fix routes every stride in the template through
# container_elem_storage_size_u64(elem_mir) and emits a byte-offset gep:
#
#     %byte_off = mul i64 %idx64, <stride>
#     %slot     = getelementptr i8, ptr %buf, i64 %byte_off
#
# so alloc, store, read and realloc are guaranteed consistent for every element
# type. See commit fix(codegen): unify late-generic Array template buffer stride.
#
# This guard is an IR-form check, not a runtime check: `Dir.glob` reliably forces
# RTA to emit late-generic Array(T)#<< templates, but the Globber runtime path has
# a separate, unrelated open bug, so we never execute the binary -- we only assert
# the emitted template uses the byte-offset form and never the typed direct-index
# form. Validated separator: a pre-fix stage2 self-compile emits 31 typed
# direct-index template stores; this reducer emits 0 after the fix.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array_late_generic_union_stride.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
IR="$TMP_DIR/repro.ll"
COMPILE_ERR="$TMP_DIR/compile.err"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

# Dir.glob pulls in Dir::Globber, whose union-valued path array is referenced via
# late-generic instantiation -> forces emit_dead_code_stub to synthesize the
# Array(T)#<< template. The program is never run (Globber has a separate open
# runtime bug); only its emitted LLVM IR is inspected.
cat >"$SRC" <<'CR'
paths = Dir.glob("/tmp/*.cr")
puts paths.size
CR

set +e
"$COMPILER" "$SRC" --emit llvm-ir -o "$TMP_DIR/repro.bin" >"$IR" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr ---"
  cat "$COMPILE_ERR"
  exit 2
fi

if [[ ! -s "$IR" ]]; then
  echo "no LLVM IR emitted on stdout"
  echo "tmp_dir: $TMP_DIR"
  exit 2
fi

# The Array template store/realloc both name the freshly-loaded buffer %buf and
# the sign-extended index %idx64. The BUGGY form indexes %buf directly with a
# typed gep (`getelementptr <T>, ptr %buf, i64 %idx64`); the FIXED form first
# computes a byte offset (`getelementptr i8, ptr %buf, i64 %byte_off`).
bad_count="$(grep -cE 'getelementptr [^,]+, ptr %buf, i64 %idx64' "$IR" || true)"
good_count="$(grep -cE 'getelementptr i8, ptr %buf, i64 %byte_off' "$IR" || true)"

if [[ "$bad_count" -ne 0 ]]; then
  echo "FAIL: $bad_count late-generic Array template store(s) use the buggy typed direct-index gep"
  echo "tmp_dir: $TMP_DIR"
  echo "--- offending lines ---"
  grep -nE 'getelementptr [^,]+, ptr %buf, i64 %idx64' "$IR" | head
  exit 1
fi

if [[ "$good_count" -lt 1 ]]; then
  echo "FAIL: no late-generic Array template emitted -- reducer no longer exercises the path"
  echo "(expected at least one 'getelementptr i8, ptr %buf, i64 %byte_off')"
  echo "tmp_dir: $TMP_DIR"
  exit 1
fi

echo "ok ($good_count byte-offset template store(s), 0 buggy)"
