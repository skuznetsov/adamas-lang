lib LibC
  fun putchar(value : Int32) : Int32
end
class DefaultReader
  def payload(value : Int32 = 65) : Int32
    value
  end
  def run : Int32
    payload
  end
end
LibC.putchar(DefaultReader.new.run)
LibC.putchar(10)
