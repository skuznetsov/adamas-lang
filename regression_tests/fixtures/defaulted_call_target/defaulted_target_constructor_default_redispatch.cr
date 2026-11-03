lib LibC
  fun putchar(value : Int32) : Int32
end

class ProcDefaultWinnerControl
  def initialize(@callback : Proc(Int32))
    LibC.putchar(73)
  end

  def self.new(callback = -> { 1 })
    LibC.putchar(69)
    7
  end
end

ProcDefaultWinnerControl.new()
ProcDefaultWinnerControl.new
LibC.putchar(10)
