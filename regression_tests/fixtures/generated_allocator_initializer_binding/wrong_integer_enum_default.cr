lib Native
  fun putchar(value : Int32) : Int32
end
enum Mode
  Checked = 65
  Reentrant = 66
end
class Parent
  def initialize(@mode : Mode = 65)
  end
  def code : Int32
    @mode.value
  end
end
class Child < Parent
end
Native.putchar(Child.new.code)
Native.putchar(10)
