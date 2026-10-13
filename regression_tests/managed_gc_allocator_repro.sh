#!/usr/bin/env bash
# Full-prelude contract regression for Crystal-managed allocation families.
#
# Upstream Crystal allocates Pointer.malloc, Array buffers, class objects,
# String::Builder buffers, and GC.malloc(_atomic) in BDWGC-managed memory.
# Explicit LibC.malloc remains outside the collector. All guards run in one
# process so an argv/runtime mismatch cannot hide later results; operations
# whose allocator precondition fails are reported and skipped. The source is
# original-valid and can be paired with Crystal 1.21 by
# setting ALLOCATOR_COMPILER_KIND=crystal.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER_KIND="${ALLOCATOR_COMPILER_KIND:-adamas}"
KEEP_TMP="${KEEP_TMP:-0}"

if [[ ! -x "$COMPILER" ]]; then
  echo "compiler is not executable: $COMPILER" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" ]]; then
  echo "safe runner is not executable: $SAFE_RUNNER" >&2
  exit 2
fi
if [[ "$COMPILER_KIND" != "adamas" && "$COMPILER_KIND" != "crystal" ]]; then
  echo "ALLOCATOR_COMPILER_KIND must be adamas or crystal" >&2
  exit 2
fi

TMP_ROOT="${TMPDIR:-/tmp}"
mkdir -p "$TMP_ROOT"
TMP_DIR="$(mktemp -d "$TMP_ROOT/managed_gc_allocator.XXXXXX")"
cleanup() {
  if [[ "$KEEP_TMP" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/managed_gc_allocator.cr"
BIN="$TMP_DIR/managed_gc_allocator.bin"
COMPILE_LOG="$TMP_DIR/compile.log"

cat >"$SRC" <<'CR'
class AllocatorProbeObject
  @defaulted : Int32 = 29

  getter defaulted
end

class AllocatorProbeLeaf
  @marker : Int32

  def initialize(@marker : Int32)
  end

  getter marker
end

class AllocatorProbeGraph
  getter values : Array(AllocatorProbeLeaf)
  getter index : Hash(String, Array(AllocatorProbeLeaf))

  def initialize(leaf : AllocatorProbeLeaf)
    @values = [leaf]
    @index = {"kept" => @values}
  end
end

def set_bit(mask : Int32, bit : Int32, value : Bool) : Int32
  value ? (mask | (1 << bit)) : mask
end

def membership_mode : Bool
  pointer_buffer = Pointer(UInt8).malloc(16)
  array = Array(UInt8).new(16)
  object = AllocatorProbeObject.new
  scanned = GC.malloc(64)
  atomic = GC.malloc_atomic(64)
  dynamic_number = 17
  dynamic_string = String.build do |io|
    io << "dynamic-"
    io << dynamic_number
  end
  native = LibC.malloc(64)

  membership_mask = 0
  membership_mask = set_bit(membership_mask, 0, GC.is_heap_ptr(pointer_buffer.as(Void*)))
  membership_mask = set_bit(membership_mask, 1, GC.is_heap_ptr(array.to_unsafe.as(Void*)))
  object_pointer = Pointer(Void).new(object.object_id)
  membership_mask = set_bit(membership_mask, 2, GC.is_heap_ptr(object_pointer))
  membership_mask = set_bit(membership_mask, 3, GC.is_heap_ptr(scanned))
  membership_mask = set_bit(membership_mask, 4, GC.is_heap_ptr(atomic))
  membership_mask = set_bit(membership_mask, 5, GC.is_heap_ptr(dynamic_string.to_unsafe.as(Void*)))
  membership_mask = set_bit(membership_mask, 6, GC.is_heap_ptr(native))

  raw_interior = scanned.as(UInt8*) + 32
  value_mask = 0
  value_mask = set_bit(value_mask, 0, pointer_buffer[0] == 0 && pointer_buffer[15] == 0)
  value_mask = set_bit(value_mask, 1, scanned.as(UInt8*)[0] == 0 && scanned.as(UInt8*)[63] == 0)
  value_mask = set_bit(value_mask, 2, object.defaulted == 29)
  value_mask = set_bit(value_mask, 3, LibGC.base(raw_interior.as(Void*)) == scanned)
  # The compiler may place an RC header before the object payload; require a
  # collector base for the address without prescribing that representation.
  value_mask = set_bit(value_mask, 4, LibGC.base(object_pointer) != Pointer(Void).null)
  value_mask = set_bit(value_mask, 5, !native.null? && LibGC.base(native) == Pointer(Void).null)

  puts "pointer_malloc_gc=#{membership_mask & 1}"
  puts "array_buffer_gc=#{(membership_mask >> 1) & 1}"
  puts "escaped_class_object_gc=#{(membership_mask >> 2) & 1}"
  puts "explicit_gc_malloc_gc=#{(membership_mask >> 3) & 1}"
  puts "explicit_gc_malloc_atomic_gc=#{(membership_mask >> 4) & 1}"
  puts "dynamic_string_buffer_gc=#{(membership_mask >> 5) & 1}"
  puts "libc_malloc_gc=#{(membership_mask >> 6) & 1}"
  puts "membership_mask=#{membership_mask}"
  puts "value_mask=#{value_mask}"
  LibC.free(native)
  STDOUT.flush
  membership_mask == 63 && value_mask == 63
end

def pointer_realloc_mode : Bool
  pointer = Pointer(UInt8).malloc(4)
  initial_zero = pointer[0] == 0 && pointer[1] == 0 && pointer[2] == 0 && pointer[3] == 0
  pointer_gc = GC.is_heap_ptr(pointer.as(Void*))
  prefix_ok = false
  grown_gc = false
  if pointer_gc
    pointer[0] = 11_u8
    pointer[1] = 22_u8
    pointer[2] = 33_u8
    pointer[3] = 44_u8
    grown = pointer.realloc(32)
    prefix_ok = grown[0] == 11_u8 && grown[1] == 22_u8 && grown[2] == 33_u8 && grown[3] == 44_u8
    grown_gc = GC.is_heap_ptr(grown.as(Void*)) && LibGC.base(grown.as(Void*)) != Pointer(Void).null
  end

  null_grown = Pointer(UInt8).null.realloc(32)
  null_gc = !null_grown.null? && GC.is_heap_ptr(null_grown.as(Void*)) && LibGC.base(null_grown.as(Void*)) != Pointer(Void).null
  null_zero = false
  if null_gc
    null_zero = true
    index = 0
    while index < 32
      null_zero = false if null_grown[index] != 0_u8
      index += 1
    end
  end

  puts "pointer_malloc_gc=#{pointer_gc ? 1 : 0}"
  puts "realloc_prefix_preserved=#{prefix_ok ? 1 : 0}"
  puts "pointer_malloc_initial_zeroed=#{initial_zero ? 1 : 0}"
  puts "realloc_result_gc=#{grown_gc ? 1 : 0}"
  puts "null_realloc_gc=#{null_gc ? 1 : 0}"
  puts "null_realloc_zeroed=#{null_zero ? 1 : 0}"
  STDOUT.flush
  pointer_gc && prefix_ok && initial_zero && grown_gc && null_gc && null_zero
end

def atomic_realloc_mode : Bool
  atomic = GC.malloc_atomic(8).as(UInt8*)
  atomic_gc = GC.is_heap_ptr(atomic.as(Void*))
  contents_ok = false
  result_gc = false
  if atomic_gc
    atomic[0] = 91_u8
    atomic[3] = 37_u8
    atomic[7] = 18_u8
    grown = GC.realloc(atomic.as(Void*), 64).as(UInt8*)
    contents_ok = grown[0] == 91_u8 && grown[3] == 37_u8 && grown[7] == 18_u8
    result_gc = GC.is_heap_ptr(grown.as(Void*)) && LibGC.base(grown.as(Void*)) != Pointer(Void).null
  end

  puts "gc_malloc_atomic_gc=#{atomic_gc ? 1 : 0}"
  puts "atomic_realloc_contents=#{contents_ok ? 1 : 0}"
  puts "atomic_realloc_result_gc=#{result_gc ? 1 : 0}"
  STDOUT.flush
  atomic_gc && contents_ok && result_gc
end

def raw_gc_free_mode : Bool
  raw = GC.malloc(24).as(UInt8*)
  raw_gc = GC.is_heap_ptr(raw.as(Void*))
  base_ok = false
  contents_ok = false
  freed = false
  if raw_gc
    # Keep the allocation headerless: store sentinels in the first word, at
    # the +8 interior address, and in the following word. The interior check
    # catches accidental RC-header traffic against a raw collector block.
    raw[0] = 0x51_u8
    raw[8] = 0xa7_u8
    raw[16] = 0x19_u8
    base_ok = LibGC.base((raw + 8).as(Void*)) == raw.as(Void*)
    contents_ok = raw[0] == 0x51_u8 && raw[8] == 0xa7_u8 && raw[16] == 0x19_u8
    GC.free(raw.as(Void*))
    freed = true
  end

  puts "raw_gc_headerless_interior_plus8=#{(raw_gc && base_ok && contents_ok) ? 1 : 0}"
  puts "explicit_gc_free_completed=#{freed ? 1 : 0}"
  STDOUT.flush
  raw_gc && base_ok && contents_ok && freed
end

def build_graph_root : Void*
  leaf = AllocatorProbeLeaf.new(0x13579)
  graph = AllocatorProbeGraph.new(leaf)
  slot = GC.malloc(sizeof(Pointer(Void)))
  slot.as(Pointer(Pointer(Void))).value = Pointer(Void).new(graph.object_id)
  slot
end

def container_liveness_mode : Bool
  root_slot = build_graph_root
  churn_index = 0
  while churn_index < 48
    temporary = GC.malloc(8192)
    temporary.as(UInt8*)[0] = (churn_index % 251 + 1).to_u8
    churn_index += 1
  end
  GC.collect
  GC.collect

  graph_pointer = root_slot.as(Pointer(Pointer(Void))).value
  graph_gc = GC.is_heap_ptr(graph_pointer)
  # Do not dereference an object whose allocator family already failed the
  # membership contract; on ARC builds the root slot is not an ARC reference.
  leaf_value_ok = false
  if graph_gc
    graph = graph_pointer.as(AllocatorProbeGraph)
    leaf_value_ok = graph.values[0].marker == 0x13579 && graph.index["kept"][0].marker == 0x13579
  end
  root_gc = GC.is_heap_ptr(root_slot) && LibGC.base(root_slot) == root_slot

  puts "scanned_root_gc=#{root_gc ? 1 : 0}"
  puts "nested_hash_gc=#{graph_gc ? 1 : 0}"
  puts "array_hash_leaf_survived=#{leaf_value_ok ? 1 : 0}"
  STDOUT.flush
  root_gc && graph_gc && leaf_value_ok
end

def builder_case(byte_count : Int32) : Bool
  builder = String::Builder.new(1)
  index = 0
  while index < byte_count
    builder.write_byte((index % 251 + 1).to_u8)
    index += 1
  end

  string = builder.to_s
  return false unless string.bytesize == byte_count
  return false unless string.to_unsafe[byte_count] == 0

  index = 0
  while index < byte_count
    return false if string.to_unsafe[index] != (index % 251 + 1).to_u8
    index += 1
  end
  true
end

def builder_boundary_mode : Bool
  builder_probe = String::Builder.new(1)
  builder_gc = LibGC.base(builder_probe.buffer.as(Void*)) != Pointer(Void).null
  ok = true
  power = 64
  while power <= 1024
    # Account for the inline String header and the trailing NUL so each write
    # sequence lands immediately below, exactly at, and just beyond a capacity
    # power-of-two boundary.
    header = String::HEADER_SIZE
    ok = false unless builder_case(power - header - 2)
    ok = false unless builder_case(power - header - 1)
    ok = false unless builder_case(power - header)
    ok = false unless builder_case(power - header + 1)
    power *= 2
  end
  puts "string_builder_buffer_gc=#{builder_gc ? 1 : 0}"
  puts "builder_power_boundaries=#{ok ? 1 : 0}"
  STDOUT.flush
  builder_gc && ok
end

failures = 0
failures += 1 unless membership_mode
failures += 1 unless pointer_realloc_mode
failures += 1 unless atomic_realloc_mode
failures += 1 unless raw_gc_free_mode
failures += 1 unless builder_boundary_mode
puts "scanned_graph_liveness_begin=1"
STDOUT.flush
failures += 1 unless container_liveness_mode
puts "failed_modes=#{failures}"
LibC.exit(failures)
CR

shasum -a 256 "$SRC"
echo "compiler=$COMPILER"
echo "compiler_kind=$COMPILER_KIND"
failures=0
compile_status=0
if [[ "$COMPILER_KIND" == "crystal" ]]; then
  LINK_FLAGS="${ALLOCATOR_CRYSTAL_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
  if RUN_SAFE_RESOURCE_FILE="$TMP_DIR/compile.resources" \
    "$SAFE_RUNNER" "$COMPILER" 240 6144 build "$SRC" -o "$BIN" "--link-flags=$LINK_FLAGS" >"$COMPILE_LOG" 2>&1; then
    compile_status=0
  else
    compile_status=$?
  fi
else
  if RUN_SAFE_RESOURCE_FILE="$TMP_DIR/compile.resources" \
    "$SAFE_RUNNER" "$COMPILER" 240 6144 "$SRC" -o "$BIN" >"$COMPILE_LOG" 2>&1; then
    compile_status=0
  else
    compile_status=$?
  fi
fi
if [[ "$compile_status" -ne 0 ]]; then
  echo "compile_status=$compile_status expected=0"
  tail -60 "$COMPILE_LOG" || true
  echo "tmp_dir=$TMP_DIR"
  exit 1
fi

echo "compile_status=0"
run_log="$TMP_DIR/run.log"
if RUN_SAFE_RESOURCE_FILE="$TMP_DIR/run.resources" \
  "$SAFE_RUNNER" "$BIN" 20 1024 >"$run_log" 2>&1; then
  run_status=0
else
  run_status=$?
fi
echo "CASE aggregate status=$run_status expected=0"
cat "$run_log"

if [[ "$run_status" -ne 0 ]]; then
  echo "managed GC allocator contract failed"
  echo "tmp_dir=$TMP_DIR"
  exit 1
fi

echo "ok: managed allocator membership, realloc, graph liveness, and builder capacity guards passed"
