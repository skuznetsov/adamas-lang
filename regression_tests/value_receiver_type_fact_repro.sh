#!/usr/bin/env bash
# A value's inferred type must not turn a bare getter into a type receiver.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal)}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/value-receiver-type-fact.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/common.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  def times(&)
    i = 0
    while i < self
      yield i
      i &+= 1
    end
    self
  end
end
struct ReceiverToken
  def initialize(@value : Int32)
  end
  def advance(delta : Int32) : Int32
    @value &+ delta
  end
  def self.tag : Int32
    41
  end
end
struct ScopeBox
  def initialize(@size : Int32)
    @reads = 0
  end
  def size : Int32
    @reads &+= 1
    @size
  end
  def reads : Int32
    @reads
  end
  def each(&)
    size.times { |i| yield i }
  end
  def grouped(&)
    (size).times { |i| yield i }
  end
  def explicit(&)
    self.size.times { |i| yield i }
  end
  def token : ReceiverToken
    ReceiverToken.new(7)
  end
  def with_token(&)
    yield token.advance(2)
  end
  def passthrough(&)
    yield
  end
  def with_nested_argument(&)
    yield passthrough { token.advance(2) }
  end
  def token_type : ReceiverToken.class
    ReceiverToken
  end
  def with_type(&)
    yield token_type.tag()
  end
end
CR

cases=()
expected=()
add_case() {
  cases+=("$1")
  expected+=("$2")
  cat "$WORK_DIR/common.cr" > "$WORK_DIR/$1.cr"
  cat >> "$WORK_DIR/$1.cr"
}

add_case colliding_caller_local 3 <<'CR'
def run : Int32
  size = 100
  sum = 0
  ScopeBox.new(3).each { |i| sum &+= i }
  sum
end
LibC.exit(run)
CR

add_case unrelated_caller_local 3 <<'CR'
def run : Int32
  count = 100
  sum = 0
  ScopeBox.new(3).each { |i| sum &+= i }
  sum
end
LibC.exit(run)
CR

add_case grouped_getter 3 <<'CR'
def run : Int32
  size = 100
  sum = 0
  ScopeBox.new(3).grouped { |i| sum &+= i }
  sum
end
LibC.exit(run)
CR

add_case explicit_getter 3 <<'CR'
def run : Int32
  size = 100
  sum = 0
  ScopeBox.new(3).explicit { |i| sum &+= i }
  sum
end
LibC.exit(run)
CR

add_case ordinary_method_arguments 9 <<'CR'
def run : Int32
  token = 100
  result = 0
  ScopeBox.new(3).with_token { |value| result = value }
  result
end
LibC.exit(run)
CR

add_case type_returning_getter 41 <<'CR'
def run : Int32
  token_type = 100
  result = 0
  ScopeBox.new(3).with_type { |value| result = value }
  result
end
LibC.exit(run)
CR

add_case class_method_type_getter 41 <<'CR'
struct ReceiverFactory
  def self.token_type : ReceiverToken.class
    ReceiverToken
  end
  def self.each(&)
    yield token_type.tag()
  end
end
def run : Int32
  token_type = 100
  result = 0
  ReceiverFactory.each { |value| result = value }
  result
end
LibC.exit(run)
CR

add_case generic_type_receiver 41 <<'CR'
struct ReceiverGeneric(T)
  def each(&)
    yield T.tag()
  end
end
result = 0
ReceiverGeneric(ReceiverToken).new.each { |value| result = value }
LibC.exit(result)
CR

add_case getter_evaluated_once 4 <<'CR'
def run : Int32
  size = 100
  box = ScopeBox.new(3)
  sum = 0
  box.each { |i| sum &+= i }
  sum &+ box.reads
end
LibC.exit(run)
CR

add_case nested_callee_in_caller_block 109 <<'CR'
def once(&)
  yield
end
def run : Int32
  token = 100
  result = 0
  once do
    ScopeBox.new(3).with_token { |value| result = value }
  end
  token &+ result
end
LibC.exit(run)
CR

add_case nested_block_in_yield_argument 109 <<'CR'
def run : Int32
  token = 100
  result = 0
  ScopeBox.new(3).with_nested_argument { |value| result = value }
  token &+ result
end
LibC.exit(run)
CR

failures=0
for ((i=0; i<${#cases[@]}; i++)); do
  name="${cases[$i]}"
  want="${expected[$i]}"
  for compiler in crystal adamas; do
    binary="$WORK_DIR/$name.$compiler"
    if [[ "$compiler" == crystal ]]; then
      command_args=("$CRYSTAL_BIN" 120 2048 build "$WORK_DIR/$name.cr" --prelude=empty -o "$binary")
    else
      command_args=("$ADAMAS_BIN" 120 2048 "$WORK_DIR/$name.cr" --no-prelude -o "$binary")
    fi
    if ! "$SAFE" "${command_args[@]}" > "$binary.build.log" 2>&1; then
      echo "FAIL $name: $compiler build"
      tail -n 12 "$binary.build.log"
      failures=$((failures + 1))
      continue
    fi
    set +e
    "$SAFE" "$binary" 5 256 > "$binary.run.log" 2>&1
    actual=$?
    set -e
    if [[ "$actual" != "$want" ]]; then
      echo "FAIL $name: $compiler exit $actual, expected $want"
      tail -n 12 "$binary.run.log"
      failures=$((failures + 1))
    fi
  done
  echo "CHECK $name (expected exit $want)"
done

cat "$WORK_DIR/common.cr" > "$WORK_DIR/reject_wrong_argument.cr"
cat >> "$WORK_DIR/reject_wrong_argument.cr" <<'CR'
struct ScopeBox
  def bad(&)
    yield token.advance(false)
  end
end
def run
  token = 100
  ScopeBox.new(3).bad { |value| value }
end
LibC.exit(run)
CR
for compiler in crystal adamas; do
  if [[ "$compiler" == crystal ]]; then
    command_args=("$CRYSTAL_BIN" 120 2048 build "$WORK_DIR/reject_wrong_argument.cr" --prelude=empty -o "$WORK_DIR/rejected")
  else
    command_args=("$ADAMAS_BIN" 120 2048 "$WORK_DIR/reject_wrong_argument.cr" --no-prelude -o "$WORK_DIR/rejected")
  fi
  rm -f "$WORK_DIR/rejected"
  set +e
  "$SAFE" "${command_args[@]}" > "$WORK_DIR/$compiler.reject.log" 2>&1
  actual=$?
  set -e
  if [[ "$actual" != 1 || -e "$WORK_DIR/rejected" ]] ||
       ! rg -q 'advance' "$WORK_DIR/$compiler.reject.log" ||
       ! rg -q 'Bool' "$WORK_DIR/$compiler.reject.log" ||
       ! rg -q 'Int32' "$WORK_DIR/$compiler.reject.log" ||
       rg -q "undefined method 'advance'" "$WORK_DIR/$compiler.reject.log"; then
    echo "FAIL reject_wrong_argument: $compiler must reject Bool for Int32 without an executable (exit $actual)"
    tail -n 12 "$WORK_DIR/$compiler.reject.log"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "FAIL: $failures value-receiver checks"
  exit 1
fi
echo "PASS: ${#cases[@]} value-receiver cases and 1 type rejection match original Crystal"
