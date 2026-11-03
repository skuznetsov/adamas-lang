lib LibC
  fun putchar(value : Int32) : Int32
end
module Defaults
  CODE = 65
  @code : Int32 = CODE
  def code : Int32; @code; end
end
class Subject
  CODE = 66
  include Defaults
  def initialize(ignore : Int32); end
end
LibC.putchar(Subject.new(3).code)
LibC.putchar(10)
