#!/usr/bin/env bash
# Class virtual calls must publish their concrete result before an enclosing
# call resolves against it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nilary-class-virtual-result.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

cat > "$WORK/both-arms.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
  fun exit(status : Int32) : NoReturn
end

class Context
end

class Binding
  @code : Int32

  def initialize(@code : Int32)
  end

  def code : Int32
    @code
  end
end

class Rows(T)
  @first : T

  def initialize(@first : T)
  end

  def first : T
    @first
  end

  def select(&)
    yield @first
    self
  end
end

abstract class Exchange
end

abstract class AMQPExchange < Exchange
  abstract def bindings_details : Rows(Binding)
end

class Direct < AMQPExchange
  def bindings_details : Rows(Binding)
    Rows(Binding).new(Binding.new(66))
  end
end

class Fanout < AMQPExchange
  def bindings_details : Rows(Binding)
    Rows(Binding).new(Binding.new(70))
  end
end

class Unrelated
  def select(&)
    yield true
    self
  end
end

def consume(items : Rows(Binding))
  LibC.putchar(items.first.code)
end

def choose_exchange(direct : Bool) : Exchange
  direct ? Direct.new : Fanout.new
end

def check(direct : Bool)
  exchange = choose_exchange(direct)
  consume(exchange.bindings_details.select { |entry| entry.code == 66 })
end

check(LibC.getpid > 0)
check(LibC.getpid < 0)
CRYSTAL

cat > "$WORK/nil-arm.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
  fun exit(status : Int32) : NoReturn
end

abstract class Source
end

class NumberSource < Source
  def entry : Int32
    66
  end
end

class NilSource < Source
  def entry : Nil
    nil
  end
end

def choose_source(number : Bool) : Source
  number ? NumberSource.new : NilSource.new
end

def consume_entry(value : Int32 | Nil)
  if value.nil?
    LibC.putchar(78)
  else
    LibC.putchar(value)
  end
end

def check(number : Bool)
  source = choose_source(number)
  consume_entry(source.entry)
end

check(LibC.getpid > 0)
check(LibC.getpid < 0)
CRYSTAL

cat > "$WORK/inherited-getter.cr" <<'CRYSTAL'
macro getter(decl)
  @{{decl}}
  def {{decl.var}} : {{decl.type}}
    @{{decl.var}}
  end
end

lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
  fun exit(status : Int32) : NoReturn
end

abstract class Source
end

abstract class NumberSourceBase < Source
  getter entry : Int32

  def initialize
    @entry = 66
  end
end

class NumberSource < NumberSourceBase
end

class NilSource < Source
  def entry : Nil
    nil
  end
end

def choose_source(number : Bool) : Source
  number ? NumberSource.new : NilSource.new
end

def consume_entry(value : Int32 | Nil)
  if value.nil?
    LibC.putchar(78)
  else
    LibC.putchar(value)
  end
end

def check(number : Bool)
  source = choose_source(number)
  consume_entry(source.entry)
end

check(LibC.getpid > 0)
check(LibC.getpid < 0)
CRYSTAL

cat > "$WORK/deferred-layout.cr" <<'CRYSTAL'
require "named_tuple"

lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
end

module Details
  abstract def details
end

abstract class Client
  include Details
end

class First < Client
  def details
    {common: 7}.merge(attributes)
  end

  def attributes
    {value: 65, first: true}
  end
end

class Second < Client
  def details
    {common: 7}.merge(attributes)
  end

  def attributes
    {value: 66, second: false}
  end
end

def choose(first : Bool) : Client
  first ? First.new : Second.new
end

def wrap(&)
  yield
end

def probe(first : Bool)
  client = choose(first)
  wrap do
    result = client.details
    if result.is_a?(NamedTuple(common: Int32, value: Int32, first: Bool))
      LibC.putchar(result[:first] && result[:common] == 7 ? result[:value] : 88)
    elsif result.is_a?(NamedTuple(common: Int32, value: Int32, second: Bool))
      LibC.putchar(!result[:second] && result[:common] == 7 ? result[:value] : 88)
    else
      LibC.putchar(88)
    end
  end
end

probe(LibC.getpid > 0)
probe(LibC.getpid < 0)
CRYSTAL
sed 's/result = client.details$/result = client.details()/' \
  "$WORK/deferred-layout.cr" > "$WORK/deferred-layout-parens.cr"

# The unannotated virtual result passes through bare self calls inside a
# NamedTuple. Picking the Int32 overload exposes a premature type hint.
cat > "$WORK/deferred-overload.cr" <<'CRYSTAL'
require "named_tuple"
@[Link("gc")]
lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
end

module Shape
  abstract def details
end
abstract class Base
  include Shape
end
class Counter(T)
  @n : T
  def initialize(@n : T)
  end
  def get(flag : Bool)
    if flag
      @n
    else
      @n
    end
  end
end

abstract class Middle < Base
  @counter : Counter(UInt64)
  def initialize
    @counter = Counter(UInt64).new(67_u64)
  end

  def details
    {code: 65, nested: fields}
  end
  private def fields
    {value: count}
  end
  private def count
    LibC.putchar(46)
    @counter.get(LibC.getpid > 0)
  end
end
class Concrete < Middle
end
class Other < Middle
  CODE = 66
  def details
    super.merge(code: CODE)
  end
end
def choose(first : Bool) : Base
  first ? Concrete.new : Other.new
end
def marker(_value : UInt64) : Int32
  85
end
def marker(_value : Int32) : Int32
  73
end
def output(row : NamedTuple)
  LibC.putchar(row[:code])
  LibC.putchar(marker(row[:nested][:value]))
end
def once(&)
  yield
end
def show(receiver : Base)
  once { output(receiver.details) }
end
show(choose(LibC.getpid > 0))
show(choose(LibC.getpid < 0))
LibC.putchar(10)
CRYSTAL
sed 's/nested: fields}/nested: fields()}/; s/value: count}/value: count()}/' \
  "$WORK/deferred-overload.cr" > "$WORK/deferred-overload-parens.cr"

# Nilary dispatch is required on every concrete receiver.
sed 's/class Fanout < AMQPExchange/class Fanout < Exchange/; /class Fanout < Exchange/{n;s/def bindings_details :/def bindings_details(required : Bool) :/;}' \
  "$WORK/both-arms.cr" > "$WORK/missing-nilary-arm.cr"
sed 's/def entry : Nil/def entry(extra : Bool) : Nil/' \
  "$WORK/nil-arm.cr" > "$WORK/missing-direct-arm.cr"
sed 's/def consume(items : Rows(Binding))/def consume(items : Bool)/; s/LibC.putchar(items.first.code)/LibC.putchar(88)/' \
  "$WORK/both-arms.cr" > "$WORK/wrong-consumer.cr"
sed 's/\.bindings_details\.select/.bindings_details().select/' \
  "$WORK/both-arms.cr" > "$WORK/parentheses.cr"

run_positive() {
  local mode="$1" probe="$2" expected="$3"
  local output="$WORK/$mode.$probe"
  "${compile[@]}" "$WORK/$probe.cr" -o "$output" > "$output.compile.log" 2>&1 || {
    cat "$output.compile.log" >&2
    return 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 \
    > "$output.stdout" 2> "$output.run.log" || {
    cat "$output.run.log" >&2
    return 1
  }
  printf '%s' "$expected" > "$output.expected"
  diff -u "$output.expected" "$output.stdout"
  printf 'PASS: %s %s\n' "$mode" "$probe"
}

run_negative() {
  local mode="$1" probe="$2" diagnostic="$3"
  local output="$WORK/$mode.$probe"
  local rc=0
  "${compile[@]}" "$WORK/$probe.cr" -o "$output" > "$output.compile.log" 2>&1 || rc=$?
  if [[ "$rc" != 1 ]] || ! rg -q "$diagnostic" "$output.compile.log"; then
    cat "$output.compile.log" >&2
    printf 'FAIL: %s %s expected a source error, got exit %s\n' "$mode" "$probe" "$rc" >&2
    return 1
  fi
  printf 'PASS: %s %s rejects\n' "$mode" "$probe"
}

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    compile=(env CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL" 20 512 build
      --prelude=empty --single-module --no-debug --link-flags="$LINK_FLAGS")
    missing_diagnostic="wrong number of arguments"
    consumer_diagnostic="expected argument #1"
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 20 512
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    missing_diagnostic="error: (undefined method|no overload matches|wrong number of arguments)"
    consumer_diagnostic="no overload matches consume"
  fi
  run_positive "$mode" both-arms BF
  run_positive "$mode" nil-arm BN
  run_positive "$mode" inherited-getter BN
  run_positive "$mode" parentheses BF
  run_positive "$mode" deferred-layout AB
  run_positive "$mode" deferred-layout-parens AB
  run_positive "$mode" deferred-overload $'.AU.BU\n'
  run_positive "$mode" deferred-overload-parens $'.AU.BU\n'
  run_negative "$mode" missing-nilary-arm "$missing_diagnostic"
  run_negative "$mode" missing-direct-arm "$missing_diagnostic"
  run_negative "$mode" wrong-consumer "$consumer_diagnostic"
done
