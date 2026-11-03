lib LibC
  fun putchar(value : Int32) : Int32
end

class GenericBox(T)
  CODE = 66

  def self.class_code : Int32
    CODE
  end
end

module Factory
  CODE = 65

  def self.read_class_code : Int32
    GenericBox(Int32).class_code
  end
end

LibC.putchar(Factory.read_class_code)
LibC.putchar(10)
