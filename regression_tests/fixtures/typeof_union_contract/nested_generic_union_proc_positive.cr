lib Native
  fun getpid : Int32
  fun putchar(value : Int32) : Int32
end

struct LeftArm
end

struct RightArm
end

struct Box(T)
  def initialize(@value : T)
  end
end

value = if Native.getpid < 0
  LeftArm.new
else
  RightArm.new
end

box = Box(LeftArm | RightArm).new(value)
emit = ->(item : typeof(box)) { Native.putchar(67) }
emit.call(box)
