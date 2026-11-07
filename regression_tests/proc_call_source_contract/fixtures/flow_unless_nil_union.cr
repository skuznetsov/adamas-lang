lib C
  fun putchar(c : Int32) : Int32
end
class Alpha
  def initialize(@code : Int32)
  end
  def code
    @code
  end
end
class Beta
  def initialize(@code : Int32)
  end
  def code
    @code
  end
end
class Stream
  def initialize(@step : Int32)
  end
  def next_value : Alpha | Beta | Nil
    @step = @step &+ 1
    if @step == 1
      Alpha.new(65)
    elsif @step == 2
      Beta.new(66)
    else
      nil
    end
  end
end
stream = Stream.new(0)
value = stream.next_value
unless value.nil?
  callback = ->(arg : typeof(value)) { arg.code }
  C.putchar(callback.call(value))
end
C.putchar(10)
