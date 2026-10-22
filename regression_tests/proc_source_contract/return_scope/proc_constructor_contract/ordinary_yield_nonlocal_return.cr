require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
def invoke_yield(&block)
  yield
end
def owner : Int32
  invoke_yield do
    return 65_i32
  end
  66_i32
end
ProcContractRuntime.putchar(owner)
ProcContractRuntime.putchar(10_i32)
