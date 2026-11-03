lib LibC
  fun putchar(value : Int32) : Int32
end
class Parent
  CODE = 65
  @code : Int32 = CODE
  def code : Int32
    @code
  end
end
class Child < Parent
  CODE = 66
end
LibC.putchar(Child.new.code)
LibC.putchar(10)
