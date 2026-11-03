lib LibC
  fun putchar(value : Int32) : Int32
end

class GenericBox(T)
  def self.class_code : Int32
    MISSING_CODE
  end
end

module Factory
  MISSING_CODE = 65

  def self.read_class_code : Int32
    GenericBox(Int32).class_code
  end
end

LibC.putchar(Factory.read_class_code)
LibC.putchar(10)
