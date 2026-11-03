lib LibC
  fun putchar(value : Int32) : Int32
end

class Parent
  VALUE = 65

  def read_value
    VALUE
  end
end

class Child < Parent
  VALUE = 66
end

LibC.putchar(Child.new.read_value)
LibC.putchar(10)
