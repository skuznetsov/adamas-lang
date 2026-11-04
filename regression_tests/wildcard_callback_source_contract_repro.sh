#!/usr/bin/env bash
# A wildcard callback gets its output from the materialized Proc. Its inputs
# retain the selected source signature, including a metaclass's value kind.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wildcard-callback.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/class_kind_anonymous.cr" <<'CR'
lib C
  fun exit(Int32) : NoReturn
end

class Answer
  def self.code : Int32
    42
  end

  def code : Int32
    7
  end
end

class Projector
  def project(& : Int32 -> _)
    (yield 1).code
  end
end

def invoke(&body : -> Int32)
  body.call
end

projector = Projector.new
C.exit(1) unless invoke { projector.project { |_| Answer.new } } == 7
C.exit(2) unless invoke { projector.project { |_| Answer } } == 42
C.exit(3) unless invoke { projector.project { |_| Answer.new } } == 7
C.exit(0)
CR

cat > "$WORK_DIR/class_kind_named.cr" <<'CR'
lib C
  fun exit(Int32) : NoReturn
end

class Answer
  def self.code : Int32
    42
  end

  def code : Int32
    7
  end
end

class Projector
  def project(&callback : Int32 -> _)
    callback.call(1).code
  end
end

def invoke(&body : -> Int32)
  body.call
end

projector = Projector.new
C.exit(1) unless invoke { projector.project { |_| Answer.new } } == 7
C.exit(2) unless invoke { projector.project { |_| Answer } } == 42
C.exit(3) unless invoke { projector.project { |_| Answer.new } } == 7
C.exit(0)
CR

cat > "$WORK_DIR/input_alias_kind.cr" <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Answer
  def self.code : Int32
    11
  end

  def code : Int32
    3
  end
end
module Lexical
  class Answer
    def self.code : Int32
      42
    end

    def code : Int32
      7
    end
  end
  alias Input = Answer.class
  class Projector
    def raw(& : Input -> _)
      yield Answer
    end
    def named(&callback : Input -> _)
      callback.call(Answer)
    end
  end
end
def invoke(&block : -> Int32)
  block.call
end
projector = Lexical::Projector.new
C.exit(1) unless invoke { projector.raw { |answer| answer.code } } == 42
C.exit(2) unless invoke { projector.named { |answer| answer.code } } == 42
C.exit(0)
CR

cat > "$WORK_DIR/input_generic_kind.cr" <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Answer
  def self.code : Int32
    42
  end

  def code : Int32
    7
  end
end
class Projector
  def raw(value : T, & : T -> _) forall T
    yield value
  end
  def named(value : T, &callback : T -> _) forall T
    callback.call(value)
  end
end
def invoke(&block : -> Int32)
  block.call
end
projector = Projector.new
C.exit(1) unless invoke { projector.raw(Answer) { |answer| answer.code } } == 42
C.exit(2) unless invoke { projector.named(Answer) { |answer| answer.code } } == 42
C.exit(3) unless invoke { projector.named(Answer.new) { |answer| answer.code } } == 7
C.exit(0)
CR

cat > "$WORK_DIR/yield_tuple_extra.cr" <<'CR'
lib C
  fun exit(Int32) : NoReturn
end
class Projector
  @@side = 0
  def self.side
    @@side
  end
  def self.record
    @@side &+= 1
    false
  end
  def project(& : Int32, Int32 -> _)
    yield *{2, 3}, Projector.record
  end
end
def invoke(&block : -> Int32)
  block.call
end
projector = Projector.new
C.exit(1) unless invoke { projector.project { |a, b| a &* b } } == 6
C.exit(2) unless Projector.side == 1
C.exit(0)
CR

cat > "$WORK_DIR/negative_yield_input_metaclass.cr" <<'CR'
class Answer
end

class Projector
  def project(& : Answer.class -> _)
    yield Answer.new
  end
end
Projector.new.project { 1 }
CR

cat > "$WORK_DIR/negative_proc_input_metaclass.cr" <<'CR'
class Answer
end

class Projector
  def project(&callback : Answer.class -> _)
    callback.call(Answer.new)
  end
end
Projector.new.project { 1 }
CR

cat > "$WORK_DIR/negative_generic_kind.cr" <<'CR'
class Answer
end

class Projector
  def project(value : T, & : T -> _) forall T
    yield Answer.new
  end
end

Projector.new.project(Answer) { 42 }
CR

cat > "$WORK_DIR/negative_yield_literal_width.cr" <<'CR'
class Projector
  def project(& : Int8 -> _)
    yield 1
  end
end

Projector.new.project { 42 }
CR

cat > "$WORK_DIR/negative_yield_short.cr" <<'CR'
class Projector
  def project(& : Int32, Int32 -> _)
    yield 1
  end
end
Projector.new.project { 1 }
CR

run_case() {
  local mode="$1" name="$2" expected_error="${3:-}" status=0
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$name.$mode"
  local log="$output.log"
  case "$mode" in
    crystal)
      CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$SAFE_RUNNER" "$CRYSTAL_BIN" 60 2048 \
        build --prelude=empty --no-debug "$source" -o "$output" > "$log" 2>&1 || status=$?
      ;;
    adamas|raw)
      (
        unset ADAMAS_DISABLE_INLINE_YIELD
        if [[ "$mode" == raw ]]; then export ADAMAS_DISABLE_INLINE_YIELD=1; fi
        "$SAFE_RUNNER" "$ADAMAS_BIN" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache \
          "$source" -o "$output"
      ) > "$log" 2>&1 || status=$?
      ;;
  esac
  if [[ -n "$expected_error" ]]; then
    if [[ "$status" != 1 ]] || ! grep -qi -- "$expected_error" "$log"; then
      printf 'FAIL %s %s expected source rejection\n' "$mode" "$name" >&2
      cat "$log" >&2
      return 1
    fi
  elif [[ "$status" != 0 ]] || ! "$SAFE_RUNNER" "$output" 5 512 >> "$log" 2>&1; then
    printf 'FAIL %s %s expected runtime exit 0\n' "$mode" "$name" >&2
    cat "$log" >&2
    return 1
  fi
  printf 'PASS %s %s\n' "$mode" "$name"
}

modes=(adamas raw)
if [[ -n "$CRYSTAL_BIN" ]]; then modes=(crystal "${modes[@]}"); fi
for mode in "${modes[@]}"; do
  run_case "$mode" class_kind_anonymous
  run_case "$mode" class_kind_named
  run_case "$mode" input_alias_kind
  run_case "$mode" input_generic_kind
  run_case "$mode" yield_tuple_extra
  run_case "$mode" negative_yield_input_metaclass 'argument #1 of yield expected to be Answer.class, not Answer'
  run_case "$mode" negative_proc_input_metaclass 'no overload matches .*Proc(Answer.class, Int32)#call.* with type Answer'
  run_case "$mode" negative_generic_kind 'argument #1 of yield expected to be Answer.class, not Answer'
  run_case "$mode" negative_yield_literal_width 'argument #1 of yield expected to be Int8, not Int32'
  run_case "$mode" negative_yield_short 'wrong number of yield arguments'
done
