lib Native
  fun getpid : Int32
  fun putchar(value : Int32) : Int32
end

struct MaybeArm
end

value = if Native.getpid < 0
  MaybeArm.new
else
  nil
end

emit = ->(item : typeof(value)) { Native.putchar(66) }
emit.call("wrong")
