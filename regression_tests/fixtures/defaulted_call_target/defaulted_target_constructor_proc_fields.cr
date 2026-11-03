lib LibC
  fun putchar(value : Int32) : Int32
end
class ProcFieldWinnerControl
  def initialize(@callback : Proc(Int32))
    LibC.putchar(74)
  end
  def self.new(callback) : Int32
    LibC.putchar(69)
  end
end
class ProcDiscoveredFieldWinnerControl
  def initialize(callback : Proc(Int32))
    @value = 76
    LibC.putchar(75)
  end
  def value : Int32
    @value
  end
  def self.new(callback) : Int32
    LibC.putchar(69)
  end
end
ProcFieldWinnerControl.new(-> { 1 })
owner = ProcDiscoveredFieldWinnerControl.new(-> { 1 })
LibC.putchar(owner.value)
LibC.putchar(10)
