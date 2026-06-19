# Regression: StaticArray(T, N) stored by value into a class field must round-trip
# its inline value bytes, not the source pointer.
#
# Root cause (fixed): StaticArray MIR registry entries are zero-sized Structs, so the
# FieldSet memcopy decision read struct_size=0 and skipped the memcopy, falling through
# to a scalar `store ptr` that wrote the source POINTER's low bytes into the 4-byte
# inline slot. The adjacent @marker survived (its store overwrote the tail), so only the
# StaticArray value was corrupt (e.g. sa0=232 sa3=1 instead of 7/9). Fixed by deriving
# the StaticArray inline size from its type name (element-storage-size * N) at the
# FieldSet memcopy site (shared with the Alloc size path).

class SAHolder
  @sa : StaticArray(UInt8, 4)
  @marker : Int32
  def initialize(@sa, @marker); end
  def sa; @sa; end            # getter: returns @sa by value
  def inner0; @sa[0]; end      # direct field index inside the class
  def inner3; @sa[3]; end
  def marker; @marker; end
end

sa = StaticArray(UInt8, 4).new(0_u8)
sa[0] = 7_u8
sa[3] = 9_u8

h = SAHolder.new(sa, 2222)
gsa = h.sa
# EXPECT: SA_FIELD inner0=7 inner3=9 getter0=7 getter3=9 marker=2222
puts "SA_FIELD inner0=#{h.inner0} inner3=#{h.inner3} getter0=#{gsa[0]} getter3=#{gsa[3]} marker=#{h.marker}"
puts "END"
