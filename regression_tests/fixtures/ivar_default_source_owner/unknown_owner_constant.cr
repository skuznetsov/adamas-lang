lib LibC
  fun putchar(value : Int32) : Int32
end
module Defaults
  @code : Int32 = ABSENT_CODE
  def code : Int32; @code; end
end
class Subject
  ABSENT_CODE = 65
  include Defaults
end
LibC.putchar(Subject.new.code)
