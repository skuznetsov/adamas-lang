#!/usr/bin/env bash
# Regression test for the `ClassName.set_crystal_type_id(ptr)` intrinsic baking
# the raw HIR TypeRef id as the runtime type_id header.
#
# Root cause: the HIR intrinsic at ast_to_hir.cr emitted
#   Literal(INT32, class_type_ref.id)
# using the *HIR* TypeRef id directly. HIR and MIR use different primitive id
# layouts (HIR places NIL at 16 -> STRING=15; MIR places NIL at 1 -> STRING=16),
# and user types are offset by +20 when crossing into MIR (convert_type). So the
# baked header was off-by-one for builtins (String 16->15, Int32 5->4, Bool 2->1,
# Char 15->14) and off-by-20 for user classes. This is the same translation
# `HIRToMIRLowering#convert_type` performs for every other value, so any object
# whose header was stamped by `set_crystal_type_id` (e.g. `String.build` ->
# `String::Builder#to_s` -> `String.set_crystal_type_id(@buffer)`) carried a
# header that disagreed with normally-allocated instances of the same type.
#
# Fix: route the baked literal through the single source of truth
# `MIR::TypeRef.from_hir(class_type_ref).id`, the same mapping convert_type now
# delegates to.
#
# Assertions:
#   1. A `String.build` result has the canonical runtime String header (16).
#   2. A user class stamped via explicit `ClassName.set_crystal_type_id` matches
#      the header a normally-allocated instance of the same class carries.
#   3. A user class stamped via bare `set_crystal_type_id` inside a class method
#      uses the same runtime id. The bare path has its own HIR lowering branch.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setid_hirmir.XXXXXX")"
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
class TidProbe
  @x : Int32 = 0

  def self.allocate_bare : Pointer(Void)
    p = Pointer(Void).malloc(16)
    set_crystal_type_id(p)
    p
  end

  def self.allocate_explicit : Pointer(Void)
    p = Pointer(Void).malloc(16)
    TidProbe.set_crystal_type_id(p)
    p
  end
end

def hdr32(p : Void*) : Int32
  p.address.unsafe_as(Pointer(Int32)).value
end

# String.build -> String::Builder#to_s -> String.set_crystal_type_id(@buffer).
# Canonical runtime String type id is 16.
built = String.build { |io| io << "hello" }
built_hdr = hdr32(built.as(Void*))

# A normally-allocated instance carries the MIR runtime id; a raw buffer stamped
# by explicit or bare set_crystal_type_id must carry the identical id.
a = TidProbe.new
a_norm = hdr32(a.as(Void*))
explicit = TidProbe.allocate_explicit
bare = TidProbe.allocate_bare
a_explicit = explicit.as(Pointer(Int32)).value
a_bare = bare.as(Pointer(Int32)).value

STDERR.puts "built_hdr=#{built_hdr}"
STDERR.puts "user_norm=#{a_norm} user_explicit=#{a_explicit} #{a_norm == a_explicit ? "OK" : "MISMATCH"}"
STDERR.puts "user_norm=#{a_norm} user_bare=#{a_bare} #{a_norm == a_bare ? "OK" : "MISMATCH"}"
STDERR.flush
STDOUT.flush
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
  exit 2
fi

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT" 2>&1
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "output:"
printf '%s\n' "$stderr_text"

built_hdr="$(printf '%s\n' "$stderr_text" | sed -n 's/^built_hdr=\([0-9-]*\).*/\1/p')"
user_matches="$(printf '%s\n' "$stderr_text" | grep -c 'user_norm=.* OK' || true)"

if [[ "$built_hdr" == "16" && "$user_matches" == "2" ]]; then
  echo "fixed: set_crystal_type_id stamps MIR runtime ids (String=16, explicit/bare user==normal)"
  exit 0
fi

echo "FAIL: expected built_hdr=16 and user_norm==user_explicit==user_bare"
cat "$RUN_OUT"
exit 1
