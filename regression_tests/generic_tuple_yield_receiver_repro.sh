#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
if [[ $# -gt 1 || ! -x "$COMPILER" ]]; then
  echo "usage: $0 [compiler]" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_tuple_yield_receiver.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/hir"
HIR="$OUT.hir"
BIN="$TMP_DIR/runtime"
NESTED_SRC="$TMP_DIR/nested_hash_reject.cr"
NESTED_OUT="$TMP_DIR/nested_hash_reject_hir"
NESTED_HIR="$NESTED_OUT.hir"
NESTED_BIN="$TMP_DIR/nested_hash_reject_runtime"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"

cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Bucket
  def initialize
    @writes = 0
  end

  def []=(key : String, value : String)
    @writes = @writes + 1
  end

  def mark
    @writes = @writes + 1
  end

  def writes : Int32
    @writes
  end
end

module TupleFlow(T)
  def each_with_object(obj : U, & : T, U ->) : U forall U
    each do |item|
      yield item, obj
    end
    obj
  end
end

class PairFlow(K, V)
  include TupleFlow(Tuple(K, V))

  def each
    yield({"key", "value"})
  end
end

module ScalarFlow(T)
  def each_with_object(obj : U, & : T, U ->) : U forall U
    each do |item|
      yield item, obj
    end
    obj
  end
end

class ScalarToken
  def initialize
    @marker = 0x123456789_i64
  end

  def accept : Int64
    @marker
  end
end

class ScalarPairFlow(K, V)
  include ScalarFlow(ScalarToken)

  def each
    yield ScalarToken.new
  end
end

class DirectFlow(K, V)
  def each_with_object(item : K, obj : V, & : K, V ->) : V
    yield item, obj
    obj
  end
end

def typed_tuple(obj : U, & : Tuple(String, String), U ->) : U forall U
  pair = {"key", "value"}
  yield pair, obj
  obj
end

def non_generic_tuple(obj : Bucket, & : Tuple(String, String), Bucket ->) : Bucket
  pair = {"key", "value"}
  yield pair, obj
  obj
end

def generic_scalar(obj : U, & : U ->) : U forall U
  yield obj
  obj
end

bucket = Bucket.new
pair_ok = false
PairFlow(String, String).new.each_with_object(bucket) do |(key, value), memo|
  memo[key] = value
end
typed_tuple(bucket) do |(key, value), memo|
  memo[key] = value
end
non_generic_tuple(bucket) do |(key, value), memo|
  memo[key] = value
end
PairFlow(String, String).new.each_with_object(bucket) do |pair, memo|
  pair_ok = pair[0] == "key" && pair[1] == "value"
  memo.mark
end
scalar_ok = false
ScalarPairFlow(Int32, Bool).new.each_with_object(bucket) do |item, memo|
  scalar_ok = item.accept == 0x123456789_i64
  memo.mark
end
direct_ok = false
DirectFlow(Int32, Bucket).new.each_with_object(-2_147_483_647, bucket) do |item, memo|
  direct_ok = item + 1 == -2_147_483_646
  memo.mark
end
generic_scalar(bucket) do |memo|
  memo.mark
end
LibC.exit(bucket.writes == 7 && pair_ok && scalar_ok && direct_ok ? 0 : 9)
CR

if ! env -u CRYSTAL_PATH ADAMAS_LLVM_CACHE=0 \
    RUN_SAFE_RESOURCE_FILE="$TMP_DIR/hir.resources" \
    "$RUN_SAFE" "$COMPILER" 180 8192 \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" \
    >"$TMP_DIR/hir.log" 2>&1; then
  echo "generic tuple yield receiver regression failed: HIR compilation failed" >&2
  tail -100 "$TMP_DIR/hir.log" >&2 || true
  exit 1
fi
if [[ ! -s "$HIR" ]]; then
  echo "generic tuple yield receiver regression failed: missing HIR" >&2
  tail -100 "$TMP_DIR/hir.log" >&2 || true
  exit 1
fi

count_fixed() {
  local file="$1"
  local needle="$2"
  awk -v needle="$needle" 'index($0, needle) { count += 1 } END { print count + 0 }' "$file"
}

void_memo_count="$(count_fixed "$HIR" 'local "memo" : 0 ')"
unspecialized_setter_calls="$(awk 'index($0, "call %") && index($0, "Bucket#[]=(") { count += 1 } END { print count + 0 }' "$HIR")"
typed_setter_calls="$(awk 'index($0, "call %") && index($0, "Bucket#[]=$String_String(") { count += 1 } END { print count + 0 }' "$HIR")"
tuple_index_gets="$(count_fixed "$HIR" '= index_get ')"
mark_calls="$(awk 'index($0, "call %") && index($0, "Bucket#mark(") { count += 1 } END { print count + 0 }' "$HIR")"
scalar_token_calls="$(awk 'index($0, "call %") && index($0, "ScalarToken#accept(") { count += 1 } END { print count + 0 }' "$HIR")"

if [[ "$void_memo_count" != "0" || "$unspecialized_setter_calls" != "0" || \
      "$typed_setter_calls" != "3" || "$tuple_index_gets" != "8" || \
      "$mark_calls" != "4" || "$scalar_token_calls" != "1" ]]; then
  echo "generic tuple yield receiver regression failed: unexpected HIR shape" >&2
  echo "void_memo=$void_memo_count unspecialized_setters=$unspecialized_setter_calls typed_setters=$typed_setter_calls tuple_index_gets=$tuple_index_gets mark_calls=$mark_calls scalar_token_calls=$scalar_token_calls" >&2
  rg -n 'local "memo"|Bucket#\[\]=|Bucket#mark|index_get' "$HIR" >&2 || true
  exit 1
fi

if ! env -u CRYSTAL_PATH ADAMAS_LLVM_CACHE=0 \
    RUN_SAFE_RESOURCE_FILE="$TMP_DIR/build.resources" \
    "$RUN_SAFE" "$COMPILER" 180 8192 "$SRC" --no-prelude -o "$BIN" \
    >"$TMP_DIR/build.log" 2>&1; then
  echo "generic tuple yield receiver regression failed: linked build failed" >&2
  tail -100 "$TMP_DIR/build.log" >&2 || true
  exit 1
fi

set +e
RUN_SAFE_RESOURCE_FILE="$TMP_DIR/run.resources" \
  "$RUN_SAFE" "$BIN" 10 512 >"$TMP_DIR/run.log" 2>&1
run_rc=$?
set -e
if [[ "$run_rc" != "0" ]]; then
  echo "generic tuple yield receiver regression failed: expected seven writes, got exit $run_rc" >&2
  cat "$TMP_DIR/run.log" >&2
  exit 1
fi

cat >"$NESTED_SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class TypeMaps
  def initialize
    @function_type_param_maps = {} of String => Hash(String, String)
  end

  def update(name : String, shape_map : Hash(String, String))
    existing = @function_type_param_maps[name]?
    @function_type_param_maps[name] = existing ? existing.merge(shape_map) : shape_map
  end

  def reject_empty_shapes : Hash(String, Hash(String, String))
    @function_type_param_maps.reject do |name, shape_map|
      shape_map.reject do |key, value|
        key.empty? || value.empty?
      end
      name.empty?
    end
  end
end

maps = TypeMaps.new
maps.update("nested", {"key" => "value"})
retained = maps.reject_empty_shapes

one_pair_ok = false
{"one" => "pair"}.each do |pair|
  one_pair_ok = pair[0] == "one" && pair[1] == "pair"
end

two_params_ok = false
{"two" => "params"}.each do |key, value|
  two_params_ok = key == "two" && value == "params"
end

pair_sum = 0
{"a" => 1, "b" => 2, "c" => 3}.each do |pair|
  next if pair[0] == "b"
  pair_sum += pair[1]
end

zero_param_iterations = 0
{"ignored" => "value"}.each do
  zero_param_iterations += 1
end

empty_iterations = 0
({} of String => String).each do |pair|
  empty_iterations += 1
end

sum = 0
{"a" => 1, "b" => 2, "c" => 3}.each do |key, value|
  next if key == "b"
  sum += value
end

LibC.exit(retained.size == 1 && one_pair_ok && two_params_ok && pair_sum == 4 &&
  zero_param_iterations == 1 && empty_iterations == 0 && sum == 4 ? 0 : 11)
CR

CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
if [[ ! -f "$CRYSTAL_STDLIB/hash.cr" ]]; then
  echo "generic tuple yield receiver regression failed: missing original Crystal stdlib at $CRYSTAL_STDLIB" >&2
  exit 1
fi

if ! CRYSTAL_PATH="$CRYSTAL_STDLIB" ADAMAS_LLVM_CACHE=0 \
    RUN_SAFE_RESOURCE_FILE="$TMP_DIR/nested_hir.resources" \
    "$RUN_SAFE" "$COMPILER" 300 8192 \
    "$NESTED_SRC" --emit hir --no-link -o "$NESTED_OUT" \
    >"$TMP_DIR/nested_hir.log" 2>&1; then
  echo "generic tuple yield receiver regression failed: nested Hash#reject HIR compile failed" >&2
  tail -100 "$TMP_DIR/nested_hir.log" >&2 || true
  exit 1
fi
if [[ ! -s "$NESTED_HIR" ]]; then
  echo "generic tuple yield receiver regression failed: missing nested Hash#reject HIR" >&2
  tail -100 "$TMP_DIR/nested_hir.log" >&2 || true
  exit 1
fi

if ! python3 - "$NESTED_HIR" <<'PY'
import re
import sys
from pathlib import Path

hir = Path(sys.argv[1]).read_text()
lines = hir.splitlines()

tuple_desc = re.compile(
    r'^\s*type\.(\d+) = Tuple Tuple\(String, Hash\(String, String\)\)\((\d+), (\d+)\)$'
)
tuple_types = {}
for line in lines:
    match = tuple_desc.match(line)
    if match:
        tuple_types[match.group(1)] = (match.group(2), match.group(3))
pair_key_type, pair_value_type = next(iter(tuple_types.values()), ('', ''))

functions = {}
current = None
body = []
for line in lines:
    if line.startswith('func @'):
        if current is not None:
            functions[current] = body
        current = line
        body = [line]
    elif current is not None:
        body.append(line)
        if line == '}':
            functions[current] = body
            current = None
            body = []
if current is not None:
    functions[current] = body

target = next((b for name, b in functions.items()
               if name.startswith('func @TypeMaps#reject_empty_shapes(')), None)

def inline_shape(body):
    if body is None:
        return False
    definitions = {}
    literals = {}
    key_fields = set()
    value_fields = set()
    allocations = {}
    index_gets = []
    setters = []
    new_hashes = set()

    for line in body:
        match = re.search(r'%(\d+) = (.*)$', line)
        if not match:
            continue
        value_id, rhs = match.groups()
        definitions[value_id] = rhs
        literal = re.search(r'^literal (-?\d+) :', rhs)
        if literal:
            literals[value_id] = int(literal.group(1))
        if re.search(r'field_get %\d+\.@key\s*:', rhs):
            key_fields.add(value_id)
        if re.search(r'field_get %\d+\.@value\s*:', rhs):
            value_fields.add(value_id)
        allocation = re.search(r'^allocate (\d+)\(%(\d+), %(\d+)\)$', rhs)
        if allocation:
            type_id, first, second = allocation.groups()
            if type_id in tuple_types:
                allocations[value_id] = (type_id, first, second)
        index_get = re.search(r'^index_get %(\d+)\[%(\d+)\] : (\d+)$', rhs)
        if index_get:
            index_gets.append((value_id, *index_get.groups()))
        setter = re.search(
            r'^call %(\d+)\.Hash\(String, Hash\(String, String\)\)#\[\]'
            r'=\$String_Hash\(String, String\)\(%(\d+), %(\d+)\)', rhs
        )
        if setter:
            setters.append(setter.groups())
        if rhs.startswith('extern_call @__adamas_hash_new('):
            new_hashes.add(value_id)

    def root(value_id):
        seen = set()
        while value_id not in seen:
            seen.add(value_id)
            rhs = definitions.get(value_id, '')
            copy = re.fullmatch(r'copy %(\d+)\s*:\s*\d+', rhs)
            if not copy:
                return value_id
            value_id = copy.group(1)
        return value_id

    key_roots = {root(value_id) for value_id in key_fields}
    value_roots = {root(value_id) for value_id in value_fields}
    tuple_roots = set()
    for value_id, (type_id, first, second) in allocations.items():
        if root(first) in key_roots and root(second) in value_roots:
            tuple_roots.add(root(value_id))

    correct_indices = {0: set(), 1: set()}
    string_key_index = False
    for value_id, base_id, index_id, result_type in index_gets:
        base_root = root(base_id)
        if base_root in key_roots:
            string_key_index = True
        if base_root not in tuple_roots:
            continue
        index_value = literals.get(root(index_id))
        if index_value in (0, 1):
            correct_indices[index_value].add((root(value_id), result_type))

    accumulator_roots = {root(value_id) for value_id in new_hashes}
    for receiver, key, value in setters:
        if (root(receiver) in accumulator_roots and
                root(key) in {value_id for value_id, typ in correct_indices[0]
                              if typ == pair_key_type} and
                root(value) in {value_id for value_id, typ in correct_indices[1]
                                if typ == pair_value_type} and
                not string_key_index):
            return True
    return False

def out_of_line_shape():
    # Keep accepting the equivalent non-inlined form: its block-local memo
    # must have the concrete Hash receiver type and feed the specialized setter.
    prefix = 'func @Hash(String, Hash(String, String))#reject$block('
    for name, body in functions.items():
        if not name.startswith(prefix):
            continue
        header_type = re.search(r'%0: (\d+)', name)
        memo = next((re.search(r'local "memo" : (\d+)', line)
                     for line in body if 'local "memo" :' in line), None)
        if header_type and memo and memo.group(1) == header_type.group(1):
            if any('Hash(String, Hash(String, String))#[]=$String_Hash(String, String)' in line
                   for line in body):
                return True
    return False

if inline_shape(target):
    print('nested Hash#reject HIR: typed tuple payload, accumulator, and setter verified')
elif out_of_line_shape():
    print('nested Hash#reject HIR: typed out-of-line memo and setter verified')
else:
    print('nested Hash#reject HIR mismatch: expected a tuple-backed typed accumulator setter',
          file=sys.stderr)
    sys.exit(1)
PY
then
  echo "generic tuple yield receiver regression failed: nested Hash#reject memo is not typed as its receiver" >&2
  rg -n -C 2 'TypeMaps#reject_empty_shapes|Hash\(String, Hash\(String, String\)\)#reject\$block|local "memo"|Hash\(String, Hash\(String, String\)\)#\[\]=' "$NESTED_HIR" >&2 || true
  exit 1
fi

if ! CRYSTAL_PATH="$CRYSTAL_STDLIB" ADAMAS_LLVM_CACHE=0 \
    RUN_SAFE_RESOURCE_FILE="$TMP_DIR/nested_build.resources" \
    "$RUN_SAFE" "$COMPILER" 300 8192 \
    "$NESTED_SRC" -o "$NESTED_BIN" \
    >"$TMP_DIR/nested_build.log" 2>&1; then
  echo "generic tuple yield receiver regression failed: nested Hash#reject linked build failed" >&2
  tail -100 "$TMP_DIR/nested_build.log" >&2 || true
  exit 1
fi

set +e
CRYSTAL_PATH="$CRYSTAL_STDLIB" RUN_SAFE_RESOURCE_FILE="$TMP_DIR/nested_run.resources" \
  "$RUN_SAFE" "$NESTED_BIN" 10 512 >"$TMP_DIR/nested_run.log" 2>&1
nested_run_rc=$?
set -e
if [[ "$nested_run_rc" != "0" ]]; then
  echo "generic tuple yield receiver regression failed: nested Hash#reject returned exit $nested_run_rc" >&2
  cat "$TMP_DIR/nested_run.log" >&2
  exit 1
fi

echo "generic_tuple_yield_receiver_repro_ok"
