lib Native
  fun getpid : Int32
  fun putchar(value : Int32) : Int32
end

struct LeftArm
  def code : Int32
    65
  end
end

struct RightArm
  def code : Int32
    66
  end
end

value = if Native.getpid < 0
  LeftArm.new
else
  RightArm.new
end

struct Box(T)
  def initialize(@item : T)
  end
  def item : T
    @item
  end
end
box = Box(LeftArm | RightArm).new(value)
emit = ->(item : typeof(box)) { Native.putchar(item.item.code) }
emit.call(Box(LeftArm | RightArm).new(LeftArm.new))
emit.call(Box(LeftArm | RightArm).new(RightArm.new))
