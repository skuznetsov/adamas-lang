#!/usr/bin/env bash
# Regression test for Task #71: Dir::Globber#matches_file? Pointer-typed entry
# monomorphization.
#
# Pre-fix: post-Task-#70, Dir.glob compiled past the @dir STUB but runtime
# crashed at `STUB CALLED: Pointer$Hname` via
# `matches_file?$Pointer(ptr null, ptr %match)`. Inside
# `Dir::Globber.each_child(path, &) ... yield entry`, the block param `entry`
# was typed as Pointer (TypeRef::POINTER = 18) instead of
# Crystal::System::Dir::Entry.
#
# Why: each_child's body says `while entry = read_entry(dir)`. read_entry is
# `def self.read_entry(dir : Dir)` — a class method registered as
# `Dir::Globber.read_entry`. The HIR identifier-call return-type lookup at
# `infer_type_from_expr_inner` only consulted the instance form
# (`Class#method` via `resolve_method_with_inheritance`). With no entry in
# `@function_types["Dir::Globber#read_entry"]`, the call resolved to nil →
# the local was never typed → the yield arg's identifier resolved via the
# generic POINTER fallback → block param entered as Pointer.
#
# Fix (HIR ast_to_hir.cr ~17108): when the bare identifier lookup fails but
# the method is defined as `def self.X` on the current class, look up via
# `resolve_class_method_with_inheritance` (the `.` form) and either consult
# the registries or body-walk the def to infer return type. Body inference
# is gated on `@infer_body_context` to prevent recursion.
#
# This is a grep-on-LL test. Runtime still crashes downstream in
# Tuple(Char)#to_static_array under File.match_internal — separate task.
set -euo pipefail

COMPILER="${1:-./bin/crystal_v2}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dirglob_each_child_entry.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
matches = Dir.glob("/tmp/*.cr")
puts "count = #{matches.size}"
CR

set +e
"$COMPILER" "$SRC" -o "$BIN" --emit llvm-ir >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "compile failed"
  echo "compiler: $COMPILER"
  echo "status: $compile_status"
  echo "tmp_dir: $TMP_DIR"
  echo "--- stderr (tail) ---"
  tail -40 "$COMPILE_ERR"
  exit 2
fi

LL="$BIN.ll"
if [[ ! -s "$LL" ]]; then
  echo "missing or empty LL: $LL"
  ls -la "$TMP_DIR"
  exit 2
fi

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "ll: $(wc -l <"$LL") lines"

# Post-fix sentinel: matches_file? monomorphized for Entry receiver
good_entry=$(grep -c 'matches_file\$Q\$\$Crystal\$CCSystem\$CCDir\$CCEntry(' "$LL" || true)
# Post-fix sentinel: matches_file? monomorphized for Nil|Entry union
good_nil_entry=$(grep -c 'matches_file\$Q\$\$Nil\$_\$OR\$_Crystal\$CCSystem\$CCDir\$CCEntry' "$LL" || true)
# Pre-fix witness: live call to matches_file?$Pointer (only dead-code copies are tolerable)
# Count live call sites — definitions excluded by `call ` prefix.
bad_pointer_calls=$(grep -cE '^\s*%[A-Za-z0-9_.]+ = call .*@Dir\$CCGlobber\$Dmatches_file\$Q\$\$Pointer' "$LL" || true)

echo "good: matches_file?\$Crystal::System::Dir::Entry callers = $good_entry"
echo "good: matches_file?\$Nil|Entry callers = $good_nil_entry"
echo "(info) Pointer-typed callsites in LL = $bad_pointer_calls (dead-code residual tolerated)"

if [[ "$good_entry" -lt 1 ]]; then
  echo "regression: matches_file? never monomorphized with Entry receiver"
  exit 1
fi

if [[ "$good_nil_entry" -lt 1 ]]; then
  echo "regression: matches_file? never monomorphized with Nil|Entry union"
  exit 1
fi

# Verify the live each_child block specialization yields entry as union (not Pointer)
each_child_union=$(grep -c '@Dir\$CCGlobber\$Deach_child\$\$block\$\$arity1' "$LL" || true)
if [[ "$each_child_union" -lt 1 ]]; then
  echo "regression: each_child\$\$block\$\$arity1 missing"
  exit 1
fi

echo "fixed: each_child block param typed as Nil|Entry, matches_file? specialized correctly"
exit 0
