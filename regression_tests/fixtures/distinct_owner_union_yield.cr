lib LibC
  fun exit(status : Int32) : NoReturn
end

class YieldLeft(T)
  def initialize(@value : T); end
  def each(& : T ->)
    yield left_value
  end
  private def left_value : T; @value; end
end

class YieldRight(T)
  def initialize(@value : T); end
  def each(& : T ->)
    yield right_value
  end
  private def right_value : T; @value + 1000; end
end

def sum_distinct(flag : Bool) : Int32
  receiver = flag ? YieldLeft(Int32).new(41) : YieldRight(Int32).new(42)
  total = 0
  receiver.each { |value| total += value }
  total
end

def first_distinct(flag : Bool) : Int32
  receiver = flag ? YieldLeft(Int32).new(41) : YieldRight(Int32).new(42)
  receiver.each { |value| return value }
  -1
end

LibC.exit(3) unless first_distinct(true) == 41
LibC.exit(4) unless first_distinct(false) == 1042
LibC.exit(1) unless sum_distinct(true) == 41
LibC.exit(2) unless sum_distinct(false) == 1042
LibC.exit(0)
