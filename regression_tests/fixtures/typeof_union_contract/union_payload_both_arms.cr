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

emit = ->(item : typeof(value)) { Native.putchar(item.code) }
emit.call(LeftArm.new)
emit.call(RightArm.new)
