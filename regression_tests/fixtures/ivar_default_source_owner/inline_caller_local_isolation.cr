lib LibC
  fun putchar(value : Int32) : Int32
end
class Subject
  def self.code : Int32; 65; end
  @code : Int32 = code
  def code : Int32; @code; end
end
def make(code : Int32)
  Subject.new
end
LibC.putchar(make(66).code)
LibC.putchar(10)
