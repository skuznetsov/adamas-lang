require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
end
alias ExplicitCallback = (Int32) -> Int32
callback = ExplicitCallback.new { |code| code &+ 1 }
ProcContractRuntime.putchar(callback.call(66_i32))
ProcContractRuntime.putchar(10_i32)
