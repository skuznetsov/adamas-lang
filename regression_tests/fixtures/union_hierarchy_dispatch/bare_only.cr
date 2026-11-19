lib UnionBareNative
  fun putchar(value : Int32) : Int32
end

abstract class BareRoot
  abstract def code : Int32
end

class BareLeft < BareRoot
  def code : Int32
    65
  end
end

class BareRight < BareRoot
  def code : Int32
    66
  end
end

class BareOther
  def code : Int32
    67
  end
end

alias BareChoice = BareRoot | BareOther

def pick(choice : Int32) : BareChoice
  if choice == 1
    BareLeft.new
  elsif choice == 2
    BareRight.new
  else
    BareOther.new
  end
end

def show(value : BareChoice)
  UnionBareNative.putchar(value.code)
end

show(pick(1))
show(pick(2))
show(pick(3))
UnionBareNative.putchar(10)
