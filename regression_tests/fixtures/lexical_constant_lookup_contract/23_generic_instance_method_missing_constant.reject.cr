lib LibC
  fun putchar(value : Int32) : Int32
end

class GenericBox(T)
  def initialize(@value : T)
  end

  def instance_code : Int32
    MISSING_CODE
  end
end

module Factory
  MISSING_CODE = 65

  def self.read_instance_code : Int32
    GenericBox(Int32).new(0).instance_code
  end
end

LibC.putchar(Factory.read_instance_code)
LibC.putchar(10)
