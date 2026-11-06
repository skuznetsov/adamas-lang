lib C
  fun putchar(c : Int32) : Int32
end

abstract struct Enum
  def value : Int
    previous_def
  end
end

enum ArgumentedValuePrevious : UInt8
  Answer = 7

  def value(tag : Int32) : Int
    C.putchar(80)
    tag
  end

  def value(tag : Int32) : Int
    C.putchar(67)
    previous_def(tag)
  end

  def route_value : Int32
    result = value(23)
    if result == 23
      C.putchar(82)
    else
      C.putchar(88)
    end
    0
  end
end

ArgumentedValuePrevious::Answer.route_value
C.putchar(10)
