lib LibC
  fun putchar(c : Int32) : Int32
end

struct RecCode
  def initialize(@code : Int32, @wide : Int64 = 123_i64)
  end

  def code : Int32
    @code
  end

  def wide : Int64
    @wide
  end
end

class SmallParser
  def initialize(@missing : Bool)
  end

  def checked_zero : RecCode
    RecCode.new(65)
  end

  def entry0(again)
    entry1(again)
  end

  def entry1(again)
    entry2(again)
  end

  def entry2(again)
    parse0(again)
  end

  def parse0(again : Bool = false) : RecCode?
    return nil if @missing
    return checked_zero unless again
    parse1(false)
  end

  def parse1(again : Bool) : RecCode?
    if again
      parse2(false)
    else
      RecCode.new(66)
    end
  end

  def parse2(again : Bool) : RecCode?
    if again
      parse3(false)
    else
      RecCode.new(67)
    end
  end

  def parse3(again : Bool) : RecCode?
    if again
      parse4(false)
    else
      RecCode.new(68)
    end
  end

  def parse4(again : Bool) : RecCode?
    if again
      parse0
    else
      RecCode.new(69)
    end
  end
end

parser = SmallParser.new(false)
parser.checked_zero
a = parser.entry0(false)
b = parser.entry0(true)
missing = SmallParser.new(true).entry0(false)
LibC.putchar(a ? a.code : 88)
LibC.putchar(b ? b.code : 89)
LibC.putchar(a ? (a.wide == 123_i64 ? 87 : 88) : 89)
LibC.putchar(missing.nil? ? 78 : 90)
LibC.putchar(10)
