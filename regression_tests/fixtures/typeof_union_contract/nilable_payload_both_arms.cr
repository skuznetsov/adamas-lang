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

maybe = if Native.getpid < 0
  LeftArm.new
else
  nil
end
emit = ->(item : typeof(maybe)) {
  if item.nil?
    Native.putchar(66)
  else
    Native.putchar(item.code)
  end
}
emit.call(LeftArm.new)
emit.call(nil)
