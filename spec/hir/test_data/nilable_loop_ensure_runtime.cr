lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

def last_value_through_ensure(values : Array(UInt32)) : UInt32?
  result : UInt32? = nil
  index = 0
  while index < values.size
    saved = index
    begin
      result = values[index]
    ensure
      index = saved
    end
    index += 1
  end
  result
end

if last_value_through_ensure([41_u32, 73_u32]) == 73_u32
  LibC.printf("generated-nilable-loop-ensure-ok\n")
end
