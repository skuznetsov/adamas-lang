lib LibC
  fun putchar(c : Int32) : Int32
end
struct RecCode
  def initialize(@code : Int32)
  end
  def code : Int32
    @code
  end
end
class SmallParser
  START = RecCode.new(65)
  def entry0(again)
    entry1(again)
  end
  def entry1(again)
    entry2(again)
  end
  def entry2(again)
    entry3(again)
  end
  def entry3(again)
    entry4(again)
  end
  def entry4(again)
    entry5(again)
  end
  def entry5(again)
    parse0(again)
  end
  def parse0(again : Bool) : RecCode
    return START unless again
    if again
      parse1(false)
    elsif again
      parse3(again)
    else
      RecCode.new(65)
    end
  end
  def parse1(again : Bool) : RecCode
    return START unless again
    if again
      parse2(false)
    elsif again
      parse4(again)
    else
      RecCode.new(66)
    end
  end
  def parse2(again : Bool) : RecCode
    return START unless again
    if again
      parse3(false)
    elsif again
      parse5(again)
    else
      RecCode.new(67)
    end
  end
  def parse3(again : Bool) : RecCode
    return START unless again
    if again
      parse4(false)
    elsif again
      parse6(again)
    else
      RecCode.new(68)
    end
  end
  def parse4(again : Bool) : RecCode
    return START unless again
    if again
      parse5(false)
    elsif again
      parse0(again)
    else
      RecCode.new(69)
    end
  end
  def parse5(again : Bool) : RecCode
    return START unless again
    if again
      parse6(false)
    elsif again
      parse1(again)
    else
      RecCode.new(70)
    end
  end
  def parse6(again : Bool) : RecCode
    return START unless again
    if again
      parse0(false)
    elsif again
      parse2(again)
    else
      RecCode.new(71)
    end
  end
end
LibC.putchar(SmallParser.new.entry0(false).code)
LibC.putchar(10)
