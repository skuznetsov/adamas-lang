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
class Stream
  def initialize(@step : Int32)
  end
  def next_value
    @step = @step &+ 1
    if @step == 1
      Alpha
    elsif @step == 2
      Alpha.new(66)
    else
      nil
    end
  end
end
s = Stream.new(0)
v = s.next_value
if v
  cb = ->(a : Alpha) { 65 }
  C.putchar(cb.call(v))
end
