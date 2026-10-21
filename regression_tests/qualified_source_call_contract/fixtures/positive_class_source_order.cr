lib LibC
  fun putchar(c : Int32) : Int32
end
class ForwardClassSource
  def self.dispatch : Int32
    self.target
  end
  def self.target : Int32
    79
  end
end
LibC.putchar(ForwardClassSource.dispatch)
