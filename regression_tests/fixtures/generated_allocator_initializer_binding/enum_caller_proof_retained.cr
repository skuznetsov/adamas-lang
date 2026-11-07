lib Native
  fun putchar(value : Int32) : Int32
end
enum Mode
  Checked = 65
  Reentrant = 66
end
class Parent
  def initialize(@mode : Mode = :checked)
  end
  def code : Int32
    @mode.value
  end
end
class Child < Parent
end
def select_code(value : Mode) : Int32
  value.value
end
def select_code(value : Int32) : Int32
  value
end
original = Mode::Reentrant
Native.putchar(Parent.new.code)
Native.putchar(select_code(original))
Native.putchar(select_code(67))
Native.putchar(10)
