lib Native
  fun getpid : Int32
  fun putchar(value : Int32) : Int32
end

struct LeftArm
end

struct RightArm
end

value = if Native.getpid < 0
  LeftArm.new
else
  RightArm.new
end

emit = ->(item : typeof(value)) { Native.putchar(65) }
emit.call(value)
