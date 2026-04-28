#!/usr/bin/env bash
# Regression test for Dir.glob STUB CALLED Dir::Globber#@dir.
#
# Before fix: stdlib `Dir.open(path : Path | String, & : self ->)` declares
# its block param via `& : self ->`. When `Dir::Globber.run` lowers the
# inner `Dir.open(path) do |dir| read_entry(dir) ... end`, the block
# parameter `dir`'s type was resolved by `block_param_types_for_call` from
# the `self` token. The substitution to the receiver type was gated on
# `receiver_type && receiver_type != TypeRef::VOID` — but `Dir.open` is a
# class method, so receiver_type is nil. `self` then fell through to
# `type_ref_for_name → resolve_type_name_in_context`, which returned
# `@current_class` of the caller (Dir::Globber). RTA then synthesized
# `Dir::Globber#read_entry(Dir::Globber)`, and `dir.@dir` inside dispatched
# to `Dir::Globber#@dir` — which does not exist → STUB CALLED at runtime.
#
# Root cause (HIR ast_to_hir.cr `block_param_types_for_call`, ~line 41492):
# self-substitution only fired when receiver_type was bound. For class
# methods called by name (`Dir.open(...)`), the owner must be recovered
# from the method name itself.
#
# Fix: when receiver_type is nil/VOID and `self` appears in resolved_names,
# fall back to `receiver_name_from_method_name(resolved_base)`. For
# `Dir.open` this extracts `Dir`, so block param `dir` gets typed as Dir.
# Now RTA synthesizes `read_entry$$Dir(Dir)`, and `dir.@dir` becomes a
# direct ivar load at Dir's offset (not Globber's STUB).
#
# This is a grep-on-LL test, not a runtime test, because Dir.glob still
# hits a downstream bug (entry-typing in each_child block param inference)
# tracked separately.
set -euo pipefail

COMPILER="${1:-./bin/crystal_v2}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dirglob_globber_self.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
LL="$TMP_DIR/repro.ll"
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

# crystal_v2 writes the LL alongside the requested output binary
LL="$BIN.ll"
if [[ ! -s "$LL" ]]; then
  echo "missing or empty LL: $LL"
  ls -la "$TMP_DIR"
  exit 2
fi

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "ll: $(wc -l <"$LL") lines"

# Pre-fix sentinel: Globber-mangled @dir getter STUB
bad_globber_atdir=$(grep -c 'Dir\$CCGlobber\$H\$ATdir' "$LL" || true)

# Pre-fix sentinel: read_entry monomorphized for Dir::Globber receiver
bad_globber_read_entry=$(grep -c 'call.*@Dir\$CCGlobber\$Dread_entry\$\$Dir\$CCGlobber' "$LL" || true)

# Post-fix sentinel: read_entry monomorphized for Dir
good_dir_read_entry=$(grep -c 'call.*@Dir\$CCGlobber\$Dread_entry\$\$Dir(' "$LL" || true)

echo "bad: Dir\$CCGlobber\$H\$ATdir refs = $bad_globber_atdir"
echo "bad: read_entry\$\$Dir\$CCGlobber callers = $bad_globber_read_entry"
echo "good: read_entry\$\$Dir callers = $good_dir_read_entry"

if [[ "$bad_globber_atdir" -ne 0 ]]; then
  echo "regression: Dir::Globber#@dir STUB present in LL"
  exit 1
fi

if [[ "$bad_globber_read_entry" -ne 0 ]]; then
  echo "regression: read_entry monomorphized with Dir::Globber receiver"
  exit 1
fi

if [[ "$good_dir_read_entry" -lt 1 ]]; then
  echo "regression: read_entry never monomorphized with Dir receiver"
  exit 1
fi

echo "fixed: Dir.open block param 'dir' resolves 'self' annotation to Dir (not caller @current_class)"
exit 0
