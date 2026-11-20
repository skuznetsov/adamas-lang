lib Native
  fun putchar(value : Int32) : Int32
end

class RangeCycle
  def entry0(start : Int32) : Int32
    entry1(start)
  end

  def entry1(start : Int32) : Int32
    entry2(start)
  end

  def entry2(start : Int32) : Int32
    evaluate(start)
  end

  def evaluate(start : Int32) : Int32
    text, ending = conditional(start)
    ending
  end

  private def conditional(start : Int32) : {String, Int32}
    end_index = matching_end(start)
    return {"", end_index &+ 1} if start == 0

    output = pieces(start &- 1)
    {output, end_index &+ 1}
  end

  private def pieces(start : Int32) : String
    part, _ = conditional(start)
    part
  end

  private def matching_end(start : Int32) : Int32
    start &+ 4
  end
end

Native.putchar(48 &+ RangeCycle.new.entry0(1))
Native.putchar(10)
