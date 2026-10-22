require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

alias SignalCallback = (Int32, Void*, Void*) ->
callback = SignalCallback.new do |code, info, data|
  ProcContractRuntime.putchar(code)
end
callback.call(66_i32, Pointer(Void).new(0_u64), Pointer(Void).new(0_u64))
ProcContractRuntime.putchar(10_i32)
