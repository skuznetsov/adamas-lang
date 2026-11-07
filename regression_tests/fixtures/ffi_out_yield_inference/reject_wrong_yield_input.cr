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
def sample(&)
  YieldNative.fill(out info)
  yield info.first
end
def consume(value : Bool) : Nil
  YieldNative.putchar(88)
end
sample { |value| consume(value) }
