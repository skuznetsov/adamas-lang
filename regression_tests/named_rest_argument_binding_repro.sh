#!/usr/bin/env bash
# Bind named arguments after a rest parameter without changing overload or evaluation order.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  export CRYSTAL_PATH="$ROOT_DIR/../crystal/src"
fi
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" ]] || exit 2
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-rest-argument-binding.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/typed_rest_body.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

def union_elements(*args : Int32 | String, tail : String = "default") : Nil
  if args[0].is_a?(String)
    Probe.putchar(65)
  else
    Probe.putchar(66)
  end
end

union_elements(7, "text", tail: "end")
union_elements(9, tail: "last")
CRYSTAL
printf 'BB' >"$WORK_DIR/typed_rest_body.expected"

cat >"$WORK_DIR/typed_overload_order.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

def choose_first(*items : Int32 | Bool, tail : String) : Nil
  Probe.putchar(65)
end

def choose_first(*items : Int32 | String, tail : String) : Nil
  Probe.putchar(66)
end

# Same two source restrictions in the opposite declaration order.
def choose_reverse(*items : Int32 | String, tail : String) : Nil
  Probe.putchar(66)
end

def choose_reverse(*items : Int32 | Bool, tail : String) : Nil
  Probe.putchar(65)
end

choose_first("x", tail: "!")
choose_reverse("y", tail: "!")
CRYSTAL
printf 'BB' >"$WORK_DIR/typed_overload_order.expected"

cat >"$WORK_DIR/mixed_overloads.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

def mixed_rest(prefix : Int32, *items, tail : Int32)
  Probe.putchar(65)
end

def mixed_rest(prefix : Int32, *items : Int32, tail : Int32)
  Probe.putchar(66)
end

def fixed_vs_rest(prefix : Int32, *items : Int32, tail : Int32)
  Probe.putchar(67)
end

def fixed_vs_rest(prefix : Int32, item : Int32, *, tail : Int32)
  Probe.putchar(68)
end

def rest_block_shape(prefix : Int32, *items : Int32, tail : Int32)
  Probe.putchar(69)
end

def rest_block_shape(prefix : Int32, *items : Int32, tail : Int32, &block)
  Probe.putchar(70)
  yield
end

mixed_rest(1, 2, tail: 3)
fixed_vs_rest(1, 2, tail: 3)
rest_block_shape(1, 2, tail: 3)
rest_block_shape(1, 2, tail: 3) { Probe.putchar(71) }
CRYSTAL
printf 'BDEFG' >"$WORK_DIR/mixed_overloads.expected"

cat >"$WORK_DIR/named_rest_forwarding.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

class ForwardingIO
end
class ForwardingException
end

def forwarding_inner(message : String, *items, exception = nil, backtrace = nil) : Nil
  if exception.is_a?(ForwardingException)
    Probe.putchar(69)
  else
    Probe.putchar(88)
  end
  if backtrace.is_a?(Nil)
    Probe.putchar(78)
  else
    Probe.putchar(88)
  end
end

def forwarding_outer(message : String, *items, to io : ForwardingIO,
                     exception = nil, backtrace = nil) : Nil
  forwarding_inner(message, *items, exception: exception, backtrace: backtrace)
end

forwarding_outer("message", "item", to: ForwardingIO.new,
  exception: ForwardingException.new)
CRYSTAL
printf 'EN' >"$WORK_DIR/named_rest_forwarding.expected"

cat >"$WORK_DIR/evaluation_order.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

def source_value(label : Int32, value : Int32) : Int32
  Probe.putchar(label)
  value
end

def consume_order(prefix : Int32, *items : Int32, left : Int32, right : Int32) : Nil
  Probe.putchar(prefix)
  Probe.putchar(items[0])
  Probe.putchar(left)
  Probe.putchar(right)
end

consume_order(source_value(49, 65), source_value(50, 66),
  right: source_value(51, 68), left: source_value(52, 67))
CRYSTAL
printf '1234ABCD' >"$WORK_DIR/evaluation_order.expected"

cat >"$WORK_DIR/default_rest_scope.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

def default_rest_scope(prefix : Int32, *items, tail : Int32, copy = prefix) : Nil
  Probe.putchar(copy)
  Probe.putchar(tail)
end

prefix = 88
default_rest_scope(65, tail: 66)
Probe.putchar(prefix)
default_rest_scope(67, 68, 69, tail: 70)
CRYSTAL
printf 'ABXCF' >"$WORK_DIR/default_rest_scope.expected"

cat >"$WORK_DIR/inherited_named_rest.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

class ParentNamedRest
  def probe(prefix : String, *items : Int32, tail : String) : Nil
    Probe.putchar(items[0])
    Probe.putchar(66)
  end
end

class ChildNamedRest < ParentNamedRest
  def probe(prefix : Int32, *items : Int32, tail : String) : Nil
    Probe.putchar(88)
  end
end

ChildNamedRest.new.probe("source", 65, tail: "tail")
CRYSTAL
printf 'AB' >"$WORK_DIR/inherited_named_rest.expected"

cat >"$WORK_DIR/named_separator.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

class NamedSeparator
  def self.new(value : Int32, *, enabled = false)
    new(value, 0, enabled: enabled)
  end
  def self.new(value : Int32, extra : Int32, *, enabled = false)
    new(value, extra, enabled)
  end
  def initialize(@value : Int32, @extra : Int32, @enabled : Bool)
  end
  def show : Nil
    Probe.putchar(@value)
  end
end

def only_named(value : Int32, *, tail : Int32) : Nil
  Probe.putchar(value)
  Probe.putchar(tail)
end
only_named(65, tail: 66)
NamedSeparator.new(67, enabled: true).show
CRYSTAL
printf 'ABC' >"$WORK_DIR/named_separator.expected"

cat >"$WORK_DIR/fixed_first_rest_sibling.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

def pick(first : String, second : String, *, tail : Int32) : Nil
  Probe.putchar(70)
end

def pick(first : Int32, *items : Int32, tail : Int32) : Nil
  Probe.putchar(82)
  Probe.putchar(first &+ 48)
  Probe.putchar(items[0] &+ 48)
  Probe.putchar(tail &+ 48)
end
pick(1, 2, tail: 9)
CRYSTAL
printf 'R129' >"$WORK_DIR/fixed_first_rest_sibling.expected"

cat >"$WORK_DIR/recursive_named_rest.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

def walk(depth : Int32, *items : String, tail : Int32) : Nil
  Probe.putchar(83)
end

def walk(depth : Int32, *items : Int32, tail : Int32) : Nil
  if depth == 0
    Probe.putchar(items[0] &+ 48)
    Probe.putchar(items[1] &+ 48)
    Probe.putchar(tail &+ 48)
  else
    Probe.putchar(82)
    walk(depth &- 1, *items, tail: tail)
  end
end
walk(1, 2, 3, tail: 9)
CRYSTAL
printf 'R239' >"$WORK_DIR/recursive_named_rest.expected"

cat >"$WORK_DIR/nested_default_scope.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

def inner(*items : Int32, marker : Int32) : Int32
  marker
end

def outer(*items : Int32, required : Int32,
          first_default : Int32 = inner(4, marker: 6),
          tail : Int32 = first_default) : Int32
  tail
end

first_default = 8
Probe.putchar(outer(1, required: 7) &+ 48)
CRYSTAL
printf '6' >"$WORK_DIR/nested_default_scope.expected"

cat >"$WORK_DIR/inherited_fixed_sibling.cr" <<'CRYSTAL'
@[Link("c")]
lib Probe
  fun putchar(value : Int32) : Int32
end

class ParentRestSibling
  def probe(prefix : String, *items : Int32, tail : String) : Nil
    Probe.putchar(items[0])
    Probe.putchar(66)
  end
end

class ChildFixedSibling < ParentRestSibling
  def probe(prefix : Int32, item : Int32, *, tail : String) : Nil
    Probe.putchar(88)
  end
end

ChildFixedSibling.new.probe("source", 65, tail: "tail")
CRYSTAL
printf 'AB' >"$WORK_DIR/inherited_fixed_sibling.expected"

TEST_CASES="${2:-typed_rest_body typed_overload_order mixed_overloads named_rest_forwarding evaluation_order default_rest_scope inherited_named_rest named_separator fixed_first_rest_sibling recursive_named_rest nested_default_scope inherited_fixed_sibling}"
for name in $TEST_CASES; do
  for mode in original candidate; do
    binary="$WORK_DIR/$name.$mode.bin"
    log="$WORK_DIR/$name.$mode.compile.log"
    if [[ "$mode" == original ]]; then
      if ! env CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
        "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/$name.cr" \
        --prelude=empty --no-debug --link-flags="${CRYSTAL_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
        -o "$binary" >"$log" 2>&1; then
        tail -30 "$log" >&2
        exit 1
      fi
    else
      if ! env CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" ADAMAS_LLVM_CACHE=0 \
        ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
        "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/$name.cr" --no-prelude \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" >"$log" 2>&1; then
        tail -30 "$log" >&2
        exit 1
      fi
    fi
    log="$WORK_DIR/$name.$mode.run.log"
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 15 512 \
      >"$WORK_DIR/$name.$mode.stdout" 2>"$log"; then
      cat "$log" >&2
      exit 1
    fi
    cmp "$WORK_DIR/$name.expected" "$WORK_DIR/$name.$mode.stdout"
    if grep -Fq '=== STDERR ===' "$log"; then
      cat "$log" >&2
      exit 1
    fi
  done
  printf 'PASS[named-rest-argument-binding:%s]: exact original-first stdout, stderr empty\n' "$name"
done
