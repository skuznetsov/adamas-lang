# Leaf-storage-POD gate narrowing (step-(a)) reducer.
#
# A struct is InlineValueCopy-eligible ONLY if every field is a primitive or enum
# leaf carrier. A raw-pointer field makes the struct NOT value-copy-safe (an inline
# copy would duplicate a live interior pointer, aliasing/escaping like a ref-owning
# struct), so a pointer-field struct must classify as ExistingLowering.
#
# Run under ADAMAS_INLINE_POD_CONTAINERS=1; the companion script greps the
# [ELEM_REPR] census lines and asserts:
#   Vec2 / Vec3  => InlineValueCopy   (all-Int32 leaf fields)
#   WithPtr      => ExistingLowering  (carries a raw Pointer(Int32) field)
struct Vec2
  getter x : Int32
  getter y : Int32

  def initialize(@x : Int32, @y : Int32)
  end
end

struct Vec3
  getter x : Int32
  getter y : Int32
  getter z : Int32

  def initialize(@x : Int32, @y : Int32, @z : Int32)
  end
end

# Raw-pointer-field struct: NOT value-copy-safe.
struct WithPtr
  @p : Pointer(Int32)
  @n : Int32

  def initialize(@p : Pointer(Int32), @n : Int32)
  end

  def deref : Int32
    @p.value + @n
  end
end

# Force all three types to be registered as Array element types.
av = [] of Vec2
av << Vec2.new(1, 2)
bv = [] of Vec3
bv << Vec3.new(3, 4, 5)

cell = Pointer(Int32).malloc(1_u64)
cell.value = 40
wv = [] of WithPtr
wv << WithPtr.new(cell, 2)

total = av[0].x + bv[0].z + wv[0].deref
STDERR.puts "total=#{total}"
STDOUT.flush
exit(0)
