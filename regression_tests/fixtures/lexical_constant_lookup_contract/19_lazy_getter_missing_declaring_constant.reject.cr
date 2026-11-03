require "object/properties"
lib LibC
  fun putchar(value : Int32) : Int32
end
module LazyGetterMissingConstantSource
  getter value : Int32 do
    DECLARING_OWNER_ONLY
  end
end

class LazyGetterMissingConstantConsumer
  DECLARING_OWNER_ONLY = 68_i32
  include LazyGetterMissingConstantSource
end

LibC.putchar(LazyGetterMissingConstantConsumer.new.value)
LibC.putchar(10)
