lib LibC
  fun putchar(value : Int32) : Int32
end
class ProcWinnerControl
  def initialize(callback : Proc(Int32))
    LibC.putchar(73)
  end
  def self.new(callback) : Int32
    LibC.putchar(69)
  end
end
ProcWinnerControl.new(-> { 1 })
LibC.putchar(10)
