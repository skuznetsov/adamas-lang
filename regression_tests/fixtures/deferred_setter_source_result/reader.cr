lib LibC
  fun putchar(value : Int32) : Int32
end
class Reader
  def run(value : Int32)
    self.pos = value
  end
  def pos=(value)
    value
  end
end
LibC.putchar(Reader.new.run(65))
LibC.putchar(10)
