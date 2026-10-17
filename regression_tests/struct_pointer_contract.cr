# Regression: one Pointer(T) contract for a wide (> 8 bytes) user struct.
# A Pointer(WidePod) obtained from pointerof(@field), from Array#to_unsafe and
# from Pointer.malloc must agree with field storage on read, write, stride
# (sizeof(T)), clear and copy independence, including a struct that nests the
# wide struct inline, and pointerof(local) of a wide struct local whose
# address is kept by another object (Channel#receive / PointerLinkedList
# shape), and the same for a C lib struct local. Expected output is produced by the original Crystal
# compiler. Lines use a single-argument STDOUT.print.
# Zeroed memory of a struct nesting a small (<= 8 bytes) struct is covered
# separately by struct_pointer_zeroed_nested_small_repro.sh.

struct WidePod
  @a : Int64
  @b : Int64
  @c : Int64

  def initialize(@a : Int64, @b : Int64, @c : Int64)
  end

  def sum : Int64
    @a + @b + @c
  end

  def bump : Nil
    @a += 1
  end
end

class PodHolder
  @item : WidePod

  def initialize(@item : WidePod)
  end

  def pointer : Pointer(WidePod)
    pointerof(@item)
  end

  def item : WidePod
    @item
  end
end

struct Slot
  @live : Bool = false
  @gen : UInt32 = 0_u32
  @pod : WidePod = WidePod.new(0_i64, 0_i64, 0_i64)

  def touch : Nil
    @live = true
    @gen &+= 1
  end

  def live? : Bool
    @live
  end

  def gen : UInt32
    @gen
  end

  def pod_pointer : Pointer(WidePod)
    pointerof(@pod)
  end
end

class PodRegistry
  @ptr : Pointer(WidePod) = Pointer(WidePod).null

  def register(pointer : Pointer(WidePod)) : Nil
    @ptr = pointer
  end

  def fill : Nil
    @ptr.value = WidePod.new(100_i64, 200_i64, 300_i64)
  end

  def bump : Nil
    @ptr.value.bump
  end

  def sum : Int64
    @ptr.value.sum
  end
end

def make_pod(a : Int64) : WidePod
  WidePod.new(a, a, a)
end

def show(label : String, value) : Nil
  STDOUT.print "#{label}=#{value}\n"
end

def observe(label : String, pointer : Pointer(WidePod)) : Nil
  show label, pointer.value.sum
end

show "sizeof", sizeof(WidePod)

# Field pointer: read, write-through, copy independence, in-place mutation.
holder = PodHolder.new(WidePod.new(1_i64, 2_i64, 3_i64))
fp = holder.pointer
observe "field.read", fp
snapshot = fp.value
fp.value = WidePod.new(10_i64, 20_i64, 30_i64)
show "field.write", holder.item.sum
show "field.snapshot", snapshot.sum
held = holder.item
fp.value.bump
show "field.bump", holder.item.sum
show "field.held", held.sum

# Array buffer: to_unsafe stride, read, write, copy independence.
items = [WidePod.new(8_i64, 80_i64, 800_i64), WidePod.new(9_i64, 90_i64, 900_i64)]
base = items.to_unsafe
show "array.stride", (base + 1).address - base.address
observe "array.read1", base + 1
show "array.index1", base[1].sum
first = items[0]
base[0] = WidePod.new(5_i64, 50_i64, 500_i64)
show "array.write0", items[0].sum
show "array.first", first.sum
items << WidePod.new(7_i64, 70_i64, 700_i64)
total = 0_i64
items.each { |pod| total += pod.sum }
show "array.total", total

# Pointer.malloc: zeroed memory, stride, clear, nested wide struct.
raw = Pointer(Slot).malloc(3)
show "raw.stride", (raw + 1).address - raw.address
show "raw.zero_gen", (raw + 1).value.gen
(raw + 1).value.touch
(raw + 2).value.touch
(raw + 2).value.touch
show "raw.touch1", "#{raw[1].live?}/#{raw[1].gen}"
show "raw.touch2", "#{raw[2].live?}/#{raw[2].gen}"
(raw + 1).value.pod_pointer.value = WidePod.new(4_i64, 40_i64, 400_i64)
observe "raw.pod1", (raw + 1).value.pod_pointer
(raw + 1).clear(1)
show "raw.clear1", "#{raw[1].live?}/#{raw[1].gen}/#{raw[1].pod_pointer.value.sum}"
show "raw.after_clear2", "#{raw[2].live?}/#{raw[2].gen}"

# pointerof(local): the pointer kept elsewhere and the local name one storage.
def local_round_trip(registry : PodRegistry) : Nil
  pod = make_pod(2_i64)
  registry.register(pointerof(pod))
  show "local.read", registry.sum
  registry.fill
  show "local.fill", pod.sum
  registry.bump
  show "local.bump", pod.sum
  copy = pointerof(pod).value
  registry.fill
  show "local.copy", copy.sum
  show "local.after", pod.sum
  direct = WidePod.new(3_i64, 30_i64, 300_i64)
  dp = pointerof(direct)
  dp.value.bump
  show "local.direct", direct.sum
end

local_round_trip(PodRegistry.new)

# pointerof(local) of a C lib struct: same contract as a wide user struct.
lib LibContractProbe
  struct Triple
    a : Int64
    b : Int64
    c : Int64
  end
end

def lib_local_round_trip : Nil
  triple = LibContractProbe::Triple.new
  triple.a = 5_i64
  tp = pointerof(triple)
  show "lib.read", tp.value.a
  tp.value.b = 9_i64
  show "lib.write", triple.b
  triple.c = 11_i64
  show "lib.back", tp.value.c
end

lib_local_round_trip
STDOUT.flush
