lib LibC
  fun putchar(value : Int32) : Int32
end

module GenericTypedHook(T)
  macro included
    def typed_marker(value : T) : Int32
      65
    end
  end
end

class GenericTypedHookHost32
  include GenericTypedHook(Int32)
end

class GenericTypedHookHost64
  include GenericTypedHook(Int64)
end

LibC.putchar(GenericTypedHookHost32.new.typed_marker(0))
LibC.putchar(GenericTypedHookHost64.new.typed_marker(0_i64))
LibC.putchar(10)
