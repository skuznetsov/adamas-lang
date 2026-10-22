lib LibC
  fun putchar(value : Int32) : Int32
end

def with_block(value : Int32, &block : Int32 -> Int32) : Int32
  block.call(value)
end

with_block 67 do |value|
  LibC.putchar(value)
end
with_block 68 { |value| LibC.putchar(value) }
with_block(69) { |value| LibC.putchar(value) }
