lib LibC
  fun putchar(value : Int32) : Int32
end
def code_source : Int32
  LibC.putchar(88)
  65
end
module Defaults
  CODE = code_source
  @code : Int32 = CODE
  def code : Int32; @code; end
end
class Subject
  CODE = 66
  include Defaults
end
LibC.putchar(Subject.new.code)
LibC.putchar(Subject.new.code)
LibC.putchar(10)
