@[Link(ldflags: "@@FFI_YIELD_HELPER_OBJECT@@")]
lib YieldNative
  struct Info
    first : Int64
    second : Int64
  end
  fun fill = adamas_ffi_yield_fill(info : Info*) : Int32
  fun fill_after = adamas_ffi_yield_after(first : Int32, second : Int64, info : Info*) : Int32
  fun fill_pointer = adamas_ffi_yield_pointer(value : Int64**) : Int32
  fun inspect = adamas_ffi_yield_inspect(value : Int64*) : Int32
  fun putchar(value : Int32) : Int32
end
class SourceProbe
  def self.sample(&)
    if YieldNative.fill(out info) == 0
      yield info.first, info.second
    end
  end
  def self.forward(&)
    sample do |first, second|
      return yield first, second
    end
  end
end
def consume(value : Tuple(Int64, Int64)) : Nil
  if value[0] == 65_i64 && value[1] == 66_i64
    YieldNative.putchar(65)
  end
end
if frame = SourceProbe.forward { |first, second| {first, second} }
  consume(frame)
end
YieldNative.putchar(10)
