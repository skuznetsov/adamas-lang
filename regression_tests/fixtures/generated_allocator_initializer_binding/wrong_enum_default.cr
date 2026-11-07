lib Native
  fun putchar(value : Int32) : Int32
end
enum Mode
  Checked = 65
  Reentrant = 66
end
enum OtherMode
  Checked = 65
end
class Parent
  def initialize(@mode : Mode = OtherMode::Checked)
  end
  def code : Int32
    @mode.value
  end
end
class Child < Parent
end
Native.putchar(Child.new.code)
Native.putchar(10)
