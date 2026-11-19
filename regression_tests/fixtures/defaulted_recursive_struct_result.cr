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
  BASE = RecCode.new(65)

  def entry0(again)
    entry1(again)
  end

  def entry1(again)
    entry2(again)
  end

  def entry2(again)
    parse0(again)
  end

  def parse0(again : Bool = false) : RecCode
    return BASE unless again
    parse1(false)
  end

  def parse1(again : Bool) : RecCode
    if again
      parse2(false)
    else
      RecCode.new(66)
    end
  end

  def parse2(again : Bool) : RecCode
    if again
      parse3(false)
    else
      RecCode.new(67)
    end
  end

  def parse3(again : Bool) : RecCode
    if again
      parse4(false)
    else
      RecCode.new(68)
    end
  end

  def parse4(again : Bool) : RecCode
    if again
      parse0
    else
      RecCode.new(69)
    end
  end
end

parser = SmallParser.new
LibC.putchar(parser.entry0(false).code)
LibC.putchar(parser.entry0(true).code)
LibC.putchar(10)
