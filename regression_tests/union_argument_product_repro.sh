#!/usr/bin/env bash
# Positional overload dispatch must cover the complete product of union arms.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/union-argument-product.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
export CRYSTAL_CACHE_DIR="$WORK/cache"
export ADAMAS_LLVM_CACHE=0
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld}"
fi

cat > "$WORK/class_call.cr" <<'CRYSTAL'
@[Link("gc")]
lib LibC
  fun putchar(value : Int32) : Int32
end

class Policy
  def self.merge(first : Policy, second : Policy) : Int32
    68
  end

  def self.merge(first : Nil, second : Policy) : Int32
    67
  end

  def self.merge(first : Policy, second : Nil) : Int32
    66
  end

  def self.merge(first : Nil, second : Nil) : Int32
    65
  end
end
class OperatorPolicy < Policy
end

def select_policy(enabled : Bool) : Policy?
  enabled ? Policy.new : nil
end
def select_operator(enabled : Bool) : OperatorPolicy?
  enabled ? OperatorPolicy.new : nil
end
def show(policy : Policy?, operator : OperatorPolicy?)
  LibC.putchar(Policy.merge(policy, operator))
end

show(select_policy(false), select_operator(false))
show(select_policy(true), select_operator(false))
show(select_policy(false), select_operator(true))
show(select_policy(true), select_operator(true))
LibC.putchar(10)
CRYSTAL

sed -e 's/def self\.merge/def merge/' -e 's/Policy\.merge(policy/Policy.new.merge(policy/' \
  "$WORK/class_call.cr" > "$WORK/instance_call.cr"
awk '/def self\.merge\(first : Nil, second : Policy/ { skip=1 }
     skip && /^  end$/ { skip=0; next }
     !skip { print }' "$WORK/class_call.cr" > "$WORK/missing_arm.cr"
awk '/^class Policy$/ {
       print
       print "  def self.merge(first, second) : Int32; 88; end"
       next
     }
     { print }' "$WORK/missing_arm.cr" > "$WORK/catchall.cr"
sed 's/def self\.merge(first : Nil, second : Policy/private &/' \
  "$WORK/class_call.cr" > "$WORK/private_class.cr"
sed 's/def merge(first : Policy, second : Policy/private &/' \
  "$WORK/instance_call.cr" > "$WORK/private_instance.cr"
sed -e 's/def merge(first : Policy, second : Policy/private &/' \
    -e '/^class Policy$/a\
  def show(policy : Policy?, operator : OperatorPolicy?)\
    LibC.putchar(self.merge(policy, operator))\
  end
' -e 's/LibC.putchar(Policy.new.merge(policy, operator))/Policy.new.show(policy, operator)/' \
  "$WORK/instance_call.cr" > "$WORK/private_self.cr"

cat > "$WORK/three_arguments.cr" <<'CRYSTAL'
@[Link("gc")]
lib LibC
  fun putchar(value : Int32) : Int32
end

def choose(a : Nil, b : Nil, c : Nil); 65; end
def choose(a : Nil, b : Nil, c : UInt8); 66_i64; end
def choose(a : Nil, b : Int64, c : Nil); 67; end
def choose(a : Nil, b : Int64, c : UInt8); 68_i64; end
def choose(a : Int32, b : Nil, c : Nil); 69; end
def choose(a : Int32, b : Nil, c : UInt8); 70_i64; end
def choose(a : Int32, b : Int64, c : Nil); 71; end
def choose(a : Int32, b : Int64, c : UInt8); 72_i64; end

class Counter
  @calls : Int32 = 0
  def calls : Int32; @calls; end
  def a(flag : Bool) : Int32?
    @calls = @calls &+ 1
    LibC.putchar(49)
    flag ? 1 : nil
  end
  def b(flag : Bool) : Int64?
    @calls = @calls &+ 1
    LibC.putchar(50)
    flag ? 1_i64 : nil
  end
  def c(flag : Bool) : UInt8?
    @calls = @calls &+ 1
    LibC.putchar(51)
    flag ? 1_u8 : nil
  end
end

def report(counter : Counter, a : Bool, b : Bool, c : Bool)
  result = choose(counter.a(a), counter.b(b), counter.c(c))
  case result
  when Int32
    LibC.putchar(result)
  when Int64
    LibC.putchar(result.to_i32!)
  end
end

counter = Counter.new
report(counter, false, false, false)
report(counter, false, false, true)
report(counter, false, true, false)
report(counter, false, true, true)
report(counter, true, false, false)
report(counter, true, false, true)
report(counter, true, true, false)
report(counter, true, true, true)
LibC.putchar(counter.calls == 24 ? 33 : 88)
LibC.putchar(10)
CRYSTAL

sed '/^def choose(a : Nil, b : Int64, c : UInt8)/d' \
  "$WORK/three_arguments.cr" > "$WORK/three_missing.cr"

# Deferred arm lowering must preserve the subtype inside the selected body.
cat > "$WORK/deferred_subtype.cr" <<'CRYSTAL'
@[Link("gc")]
lib LibC
  fun putchar(value : Int32) : Int32
end

class Policy
  def self.marker : Int32; 91; end

  def self.merge_definitions(first : Policy, second : Policy) : Int32
    typeof(second).marker &+ 1
  end

  def self.merge_definitions(first : Nil, second : Policy) : Int32
    typeof(second).marker
  end

  def self.merge_definitions(first : Policy, second : Nil) : Int32
    66
  end

  def self.merge_definitions(first : Nil, second : Nil) : Int32
    65
  end
end
class OperatorPolicy < Policy
  def self.marker : Int32; 67; end
end

def select_policy(enabled : Bool) : Policy?
  enabled ? Policy.new : nil
end
def select_operator(enabled : Bool) : OperatorPolicy?
  enabled ? OperatorPolicy.new : nil
end
def inside(&)
  yield
end

def show(policy : Policy?, operator : OperatorPolicy?)
  inside do
    LibC.putchar(Policy.merge_definitions(policy, operator))
  end
end

# The same source method also needs a parent-typed specialization.
LibC.putchar(Policy.merge_definitions(Policy.new, Policy.new))
show(select_policy(false), select_operator(false))
show(select_policy(true), select_operator(false))
show(select_policy(false), select_operator(true))
show(select_policy(true), select_operator(true))
LibC.putchar(Policy.merge_definitions(Policy.new, Policy.new))
LibC.putchar(10)
CRYSTAL

compile() {
  local impl="$1" source="$2" output="$3"
  if [[ "$impl" == original ]]; then
    "$SAFE" "$ORIGINAL" 25 1024 build --prelude=empty "$source" -o "$output"
  else
    "$SAFE" "$CANDIDATE" 25 2048 "$source" --no-prelude --no-ast-cache --no-llvm-cache -o "$output"
  fi
}

positive() {
  local name="$1" expected="$2" impl out
  printf '%s\n' "$expected" > "$WORK/$name.expected"
  for impl in original candidate; do
    out="$WORK/$name.$impl"
    if ! compile "$impl" "$WORK/$name.cr" "$out" > "$out.compile" 2>&1; then
      cat "$out.compile" >&2
      return 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$out" 5 512 > "$out.stdout" 2> "$out.run"; then
      cat "$out.run" >&2
      return 1
    fi
    diff -u "$WORK/$name.expected" "$out.stdout"
    printf 'PASS %s %s\n' "$name" "$impl"
  done
}

negative() {
  local name="$1" original_error="$2" candidate_error="$3" impl out expected rc
  for impl in original candidate; do
    out="$WORK/$name.$impl"
    expected="$candidate_error"
    if [[ "$impl" == original ]]; then
      expected="$original_error"
    fi
    rc=0
    compile "$impl" "$WORK/$name.cr" "$out" > "$out.compile" 2>&1 || rc=$?
    if [[ "$rc" -ne 1 ]] || ! grep -aEq "$expected" "$out.compile"; then
      cat "$out.compile" >&2
      return 1
    fi
    printf 'PASS %s %s rejects\n' "$name" "$impl"
  done
}

positive class_call ABCD
positive instance_call ABCD
positive catchall ABXD
positive private_self ABCD
positive deferred_subtype '\ABCD\'
positive three_arguments '123A123B123C123D123E123F123G123H!'
negative missing_arm 'Error: .*merge' 'error: no overload matches Policy\.merge'
negative three_missing 'Error: .*choose' 'error: no overload matches choose'
negative private_class "Error: private method 'merge'" "error: private method 'merge'"
negative private_instance "Error: private method 'merge'" "error: private method 'merge'"
