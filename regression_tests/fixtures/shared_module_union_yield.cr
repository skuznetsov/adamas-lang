lib C
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  C.exit(97)
end

module SharedVisit(T)
  def visit(& : T ->)
    yield value
  end
end

class LeftVisit(T)
  include SharedVisit(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end

class RightVisit(T)
  include SharedVisit(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end

def check_shared_visit(flag : Bool) : Int32
  iterator = if flag
    LeftVisit(Int32).new(41)
  else
    RightVisit(Int32).new(42)
  end
  total = 0
  iterator.visit { |value| total += value }
  total
end

class ThirdVisit(T)
  include SharedVisit(T)
  def initialize(@value : T); end
  def value : T; @value; end
end

def check_three_shared_visit(selector : Int32) : Int32
  iterator = if selector == 0
    LeftVisit(Int32).new(10)
  elsif selector == 1
    RightVisit(Int32).new(20)
  else
    ThirdVisit(Int32).new(30)
  end
  total = 1
  count = 0
  iterator.visit do |value|
    total += value
    count += 1
  end
  total + count
end

def return_from_shared_visit(flag : Bool) : Int32
  iterator = flag ? LeftVisit(Int32).new(10) : RightVisit(Int32).new(20)
  iterator.visit { |value| return value + 3 }
  0
end

C.exit(11) if check_three_shared_visit(0) != 12
C.exit(12) if check_three_shared_visit(1) != 22
C.exit(13) if check_three_shared_visit(2) != 32
C.exit(14) if return_from_shared_visit(true) != 13
C.exit(15) if return_from_shared_visit(false) != 23
C.exit(7) if check_shared_visit(true) != 41
C.exit(8) if check_shared_visit(false) != 42
C.exit(0)
