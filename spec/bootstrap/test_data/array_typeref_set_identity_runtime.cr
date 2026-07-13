lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

struct TypeRef
  getter id : UInt32

  def initialize(@id : UInt32)
  end
end

uint_values = Array(UInt32).new
17.times do |index|
  uint_values << index.to_u32
end
uint_unique = uint_values.uniq

small_values = Array(TypeRef).new
16.times do |index|
  small_values << TypeRef.new(index.to_u32)
end
small_unique = small_values.uniq

large_values = Array(TypeRef).new
17.times do |index|
  large_values << TypeRef.new(index.to_u32)
end
large_unique = large_values.uniq

LibC.printf(
  "ADAMAS_ARRAY_TYPEREF_SET_OK:uint=%u,%u,%d;small=%u,%u,%d;large=%u,%u,%d\n",
  uint_unique.first,
  uint_unique.last,
  uint_unique.size,
  small_unique.first.id,
  small_unique.last.id,
  small_unique.size,
  large_unique.first.id,
  large_unique.last.id,
  large_unique.size
)
