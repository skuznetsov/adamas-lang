require "proc"

lib ProcUnpackShadowRuntime
  fun putchar(value : Int32) : Int32
end

outer = 65_i32
bias = 1_i32
ProcUnpackShadowRuntime.putchar(outer)

callback = ->(outer : Int32) : Int32 { outer &+ bias }

ProcUnpackShadowRuntime.putchar(outer)
result = callback.call(32_i32)
ProcUnpackShadowRuntime.putchar(result)
ProcUnpackShadowRuntime.putchar(outer)
ProcUnpackShadowRuntime.putchar(10_i32)
