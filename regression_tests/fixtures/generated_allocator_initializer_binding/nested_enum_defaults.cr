lib Native
  fun putchar(value : Int32) : Int32
end
enum OuterMode
  Checked = 65
end
enum InnerMode
  Checked = 66
end
class InnerRecord
  def initialize(@mode : InnerMode = :checked)
  end
  def code : Int32
    @mode.value
  end
end
class OuterRecord
  def initialize(@mode : OuterMode = :checked)
    Native.putchar(InnerRecord.new.code)
  end
  def code : Int32
    @mode.value
  end
end
Native.putchar(OuterRecord.new.code)
Native.putchar(10)
