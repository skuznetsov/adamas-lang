require "object/properties"
lib LibC
  fun putchar(value : Int32) : Int32
end
module LazyGetterConstantSource
  VALUE = 65_i32

  getter value : Int32 do
    VALUE
  end
end

class LazyGetterConstantConsumer
  VALUE = 66_i32
  include LazyGetterConstantSource
end

LibC.putchar(LazyGetterConstantConsumer.new.value)
LibC.putchar(10)
