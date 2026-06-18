#!/usr/bin/env bash
# Baseline-correctness reducers for the ARC-owned-String (E) work — E-R2..E-R10.
#
# These lock the OBSERVABLE STRING CORRECTNESS of the common dynamic-String
# producer/consumer shapes at baseline-D (the two-heap GC fix `e635fbc4`, where
# dynamic Strings leak-to-exit and nothing is freed). They MUST pass here, and
# MUST keep passing once P2 flips the ARC-owned-String ABI (`ADAMAS_ARC_STRING`)
# and begins emitting scope-end `rc_dec` drop sites — i.e. they are the
# regression guard against premature free / double free / borrowed-return UAF
# introduced by the drop-site emission (SDD §8, docs/arc_owned_string_sdd.md).
#
# Cases (one compile, one run, full-line assert — pinpoints the diverging ID):
#   E-R2  Hash(String,Int32) insert/overwrite/delete    — container store/evict rc
#   E-R3  Array(String) push/pop/clear                   — array store/evict rc
#   E-R4  return fresh String, use after 2nd allocation  — call-return ownership
#   E-R5  return a field String, drop the original owner — borrowed-return retain
#   E-R6  to_slice, read bytes after the String drops    — slice-alias no early free
#   E-R7  String.build result used after a 2nd build     — Builder#to_s transfer
#   E-R8  literal passed/stored/dropped                  — literal not corrupted
#   E-R9  String + String chains incl. concat-with-empty — intermediate/passthrough rc
#   E-R10 string in a global (CONST) root, read late     — global ownership
#
# At baseline-D every one of these passes trivially (no Strings are freed). The
# value is the locked expectation: any P2 drop-site that frees one of these too
# early (E-R4/R5/R6) or double-frees a passthrough/literal (E-R8/R9) flips the
# assertion. E-R1/E-R12/E-R13/E-R14 (RSS / watchpoint) are gate-ON only — P2+.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arc_owned_str.XXXXXX")"
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
def make_fresh(n : Int32) : String
  "fresh-#{n}"
end

class Holder
  @name : String
  def initialize(@name : String)
  end

  def name : String
    @name
  end
end

# E-R5: the Holder local is the original owner of @name; it goes out of scope at
# the method return, but the returned field String must stay live (borrowed-return).
def get_name : String
  h = Holder.new("held-name")
  h.name
end

# E-R6: the source String is a local; it drops at the method return, but the
# returned slice aliases its bytes and must not be freed out from under us.
def get_slice : Slice(UInt8)
  s = "slice-src"
  s.to_slice
end

def build_str(n : Int32) : String
  String.build do |io|
    io << "built-"
    io << n.to_s
  end
end

LIT = "literal-const"

def pass_lit(s : String) : String
  s
end

# A true global root: a CONST-held container. A fresh (non-literal) String stored
# here must survive to end-of-run even as locals churn.
GLOBAL_ROOT = [] of String

# --- E-R2: Hash(String,Int32) insert / overwrite / delete / re-insert ---
h = {} of String => Int32
h["alpha"] = 1
h["beta"] = 2
h["alpha"] = 10
h["gamma"] = 3
h.delete("beta")
h["beta"] = 20
beta_v = h.has_key?("beta") ? h["beta"] : -1
r2 = "#{h["alpha"]}-#{beta_v}-#{h["gamma"]}-#{h.size}"

# --- E-R3: Array(String) push / pop / clear ---
a = [] of String
a << "x1"
a << "x2"
a << "x3"
popped = a.pop
a << "x4"
cleared = ["k1", "k2"]
cleared.clear
r3 = "#{popped}|#{a.join(",")}|#{cleared.size}"

# --- E-R4: fresh return, used after a second allocation ---
f = make_fresh(7)
dummy4 = make_fresh(99)
r4 = "#{f}/#{dummy4}"

# --- E-R5: borrowed (field) return, original owner dropped ---
g = get_name
dummy5 = make_fresh(123)
r5 = "#{g}/#{dummy5.size}"

# --- E-R6: slice alias outlives its backing String ---
sl = get_slice
dummy6 = make_fresh(456)
r6 = "#{sl.size}:#{sl[0]}:#{sl[sl.size - 1]}"

# --- E-R7: Builder result used after a second build ---
b1 = build_str(5)
b2 = build_str(6)
r7 = "#{b1}|#{b2}"

# --- E-R8: literal passed / stored / dropped ---
arr_lit = [] of String
arr_lit << pass_lit(LIT)
arr_lit << "inline-literal"
r8 = "#{arr_lit[0]}/#{arr_lit[1]}"

# --- E-R9: concat chains, including concat-with-empty (null passthrough) ---
p1 = "foo"
p2 = "bar"
c = p1 + p2 + "baz"
ce = "x" + ""
ce2 = "" + "y"
r9 = "#{c}/#{ce}/#{ce2}"

# --- E-R10: fresh String reachable only via a global (CONST) root, read late ---
GLOBAL_ROOT << make_fresh(789)
extra = make_fresh(1000)
r10 = "#{GLOBAL_ROOT[0]}/#{extra.size}"

STDERR.puts "R2=#{r2} R3=#{r3} R4=#{r4} R5=#{r5} R6=#{r6} R7=#{r7} R8=#{r8} R9=#{r9} R10=#{r10}"
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

# E-R2  h: alpha=10, beta re-inserted=20, gamma=3, size=3        -> "10-20-3-3"
# E-R3  popped="x3", a=[x1,x2,x4], cleared empty                 -> "x3|x1,x2,x4|0"
# E-R4  fresh-7 intact after a 2nd allocation                    -> "fresh-7/fresh-99"
# E-R5  borrowed field "held-name" intact; dummy5="fresh-123"(9) -> "held-name/9"
# E-R6  "slice-src" is 9 bytes, [0]='s'=115, [8]='c'=99          -> "9:115:99"
# E-R7  both Builder results intact                              -> "built-5|built-6"
# E-R8  literal + inline literal intact                          -> "literal-const/inline-literal"
# E-R9  chain + two empty-concats (passthrough)                  -> "foobarbaz/x/y"
# E-R10 fresh-789 via CONST root; extra="fresh-1000"(10)         -> "fresh-789/10"
expected="R2=10-20-3-3 R3=x3|x1,x2,x4|0 R4=fresh-7/fresh-99 R5=held-name/9 R6=9:115:99 R7=built-5|built-6 R8=literal-const/inline-literal R9=foobarbaz/x/y R10=fresh-789/10"

if [[ "$stderr_text" == "$expected" ]]; then
  echo "PASS: ARC-owned-String baseline correctness (E-R2..E-R10) holds at baseline-D"
  exit 0
fi

echo "FAIL: output mismatch"
echo "expected: $expected"
echo "--- full run output ---"
cat "$RUN_OUT"
exit 1
