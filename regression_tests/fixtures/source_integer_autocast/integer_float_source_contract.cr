lib ProbeC
  fun exit(code : Int32) : NoReturn
  fun putchar(value : Int32) : Int32
end

struct FloatSlot(T)
  def put(value : T) : T
    value
  end
end

struct FloatOverload
  def put(value : Float64) : Int32
    1
  end

  def put(value : Int32) : Int32
    2
  end
end

def wide(value : Float64) : Float64
  value
end

def narrow(value : Float32) : Float32
  value
end

s16 = -101_i16
u32 = 4_000_000_001_u32
ProbeC.exit(1) unless FloatSlot(Float64).new.put(0) == 0.0
ProbeC.exit(2) unless wide(-7_i64) == -7.0
ProbeC.exit(3) unless narrow(16_777_217) == 16_777_216.0_f32
ProbeC.exit(4) unless wide(u32) == 4_000_000_001.0
ProbeC.exit(5) unless narrow(s16) == -101.0_f32
ProbeC.exit(6) unless wide(value: 9_u64) == 9.0
ProbeC.exit(7) unless FloatOverload.new.put(0) == 2
ProbeC.putchar(65)
ProbeC.putchar(10)
