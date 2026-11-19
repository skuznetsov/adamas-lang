lib LibC
  fun putchar(c : Int32) : Int32
end

abstract class ParseResult
  abstract def code : Int32
end

class FirstResult < ParseResult
  def code : Int32
    65
  end
end

class SecondResult < ParseResult
  def code : Int32
    66
  end
end

class Reader
  def entry0(again, first)
    entry1(again, first)
  end

  def entry1(again, first)
    entry2(again, first)
  end

  def entry2(again, first)
    parse(again, first)
  end

  def parse(again : Bool, first : Bool) : ParseResult
    return default_result unless again
    return FirstResult.new if first
    if value = resolve(false, false)
      return value
    end
    FirstResult.new
  end

  def resolve(again : Bool, missing : Bool) : ParseResult?
    return nil if missing
    path(again)
  end

  def path(again : Bool) : ParseResult?
    symbol(again)
  end

  def symbol(again : Bool) : ParseResult?
    parse(again, false)
  end

  def default_result : SecondResult
    SecondResult.new
  end
end

reader = Reader.new
LibC.putchar(reader.entry0(true, true).code)
LibC.putchar(reader.entry0(true, false).code)
LibC.putchar(10)
