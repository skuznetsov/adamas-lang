#!/usr/bin/env bash
# Regression test for compiling macro-built `Slice(T).literal` tables — the
# stdlib `String::CHAR_TO_DIGIT` pattern.
#
# Before fix, several independent bugs collapsed such tables:
#  1. The parser kept only the FIRST statement of a multi-statement `{% ... %}`
#     directive (the table-builder block) and fast-forwarded over the rest, so
#     the `each`/`[]=` mutations that populate the table never ran.
#  2. The macro evaluator had no `Array#each`/`each_with_index`, no
#     `MacroArrayValue#[]=`, and did not materialize a `Range` used as a value
#     (`(0...256).map { ... }`), so the builder produced an empty/0-length array.
#  3. The class-body macro-if "flag text" fast path did not thread macro locals
#     (`{% table = ... %}`) into a later `{{ table.splat }}` interpolation, so
#     the splat saw a missing array and collapsed to a single element.
#  4. `pack_splat_args_for_call` packed the splat into a Tuple for the
#     `slice_literal` primitive, collapsing the literal to one element holding
#     the tuple (wrong @size + garbage data).
#  5. Negative literals (`-1`) in the macro-reparsed table builder mis-lowered:
#     the unary-operator text was read via stale source-span extraction whose
#     offsets are relative to the transient reparse buffer, yielding a garbage
#     char that lowered `-1` as `1.<garbagechar>()` -> runtime STUB CALLED.
#     Fixed by owning UnaryNode.operator bytes and preferring them.
#
# This script exercises the full end-to-end path with both a positive-fill table
# (flag-path local threading) and a CHAR_TO_DIGIT-shaped negative-fill table.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slice_lit_table.XXXXXX")"
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
class Foo
  # Positive-fill table built across an each-block mutating a captured local,
  # then splatted into a Slice.literal (flag-path local threading + splat).
  {% if compare_versions(Crystal::VERSION, "1.16.0") >= 0 %}
    {%
      table = (0...8).map { 0 }
      (0...3).each do |i|
        table[i] = i + 100
      end
    %}
    TBL = Slice(Int8).literal({{ table.splat }})
  {% else %}
    TBL = Slice(Int8).literal(7_i8, 8_i8, 9_i8, 10_i8, 11_i8)
  {% end %}

  # CHAR_TO_DIGIT-shaped table: 256 elements, -1 fill (exercises the negative
  # literal reparse path), with digit/letter slots set.
  {% if compare_versions(Crystal::VERSION, "1.16.0") >= 0 %}
    {%
      d = (0...256).map { -1 }
      (0...10).each do |i|
        d[48 + i] = i
      end
      (0...26).each do |i|
        d[65 + i] = i + 10
        d[97 + i] = i + 10
      end
    %}
    DIG = Slice(Int8).literal({{ d.splat }})
  {% end %}
end

STDERR.puts "TBL_SIZE=#{Foo::TBL.size} t0=#{Foo::TBL.to_unsafe[0]} t1=#{Foo::TBL.to_unsafe[1]} t2=#{Foo::TBL.to_unsafe[2]}"
STDERR.puts "DIG_SIZE=#{Foo::DIG.size} d0=#{Foo::DIG.to_unsafe[48]} d9=#{Foo::DIG.to_unsafe[57]} da=#{Foo::DIG.to_unsafe[97]} df=#{Foo::DIG.to_unsafe[102]} dz=#{Foo::DIG.to_unsafe[122]}"
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

./scripts/run_safe.sh "$BIN" 5 256 >"$RUN_OUT"
stderr_text="$(awk '/^=== STDERR ===/{flag=1;next}/^\[EXIT/{flag=0}flag' "$RUN_OUT" | tr -d '\r' | sed '/^$/d')"

echo "compiler: $COMPILER"
echo "tmp_dir: $TMP_DIR"
echo "stderr:"
printf '%s\n' "$stderr_text"

# TBL: 8 elements, [0..2] = 100,101,102
# DIG: 256 elements; '0'(48)=0, '9'(57)=9, 'a'(97)=10, 'f'(102)=15, 'z'(122)=35
expected_tbl="TBL_SIZE=8 t0=100 t1=101 t2=102"
expected_dig="DIG_SIZE=256 d0=0 d9=9 da=10 df=15 dz=35"

if grep -qF "$expected_tbl" <<<"$stderr_text" && grep -qF "$expected_dig" <<<"$stderr_text"; then
  echo "fixed: macro-built Slice.literal tables compile correctly"
  exit 0
fi

echo "unexpected output"
echo "expected TBL: $expected_tbl"
echo "expected DIG: $expected_dig"
cat "$RUN_OUT"
exit 1
