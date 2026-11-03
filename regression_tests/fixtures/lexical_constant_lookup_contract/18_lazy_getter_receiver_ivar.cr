require "object/properties"
lib LibC
  fun putchar(value : Int32) : Int32
end
module LazyGetterReceiverIvarSource
  getter value : Int32 do
    @seed
  end
end

class LazyGetterReceiverIvarConsumer
  include LazyGetterReceiverIvarSource

  def initialize(@seed : Int32)
  end
end

LibC.putchar(LazyGetterReceiverIvarConsumer.new(67_i32).value)
LibC.putchar(10)
