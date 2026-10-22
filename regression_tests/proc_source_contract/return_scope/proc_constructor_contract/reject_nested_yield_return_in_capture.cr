require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
def invoke_yield(&block)
  yield
end
def make_callback : Proc(Int32)
  Proc(Int32).new do
    invoke_yield do
      return 73_i32
    end
    74_i32
  end
end
make_callback
