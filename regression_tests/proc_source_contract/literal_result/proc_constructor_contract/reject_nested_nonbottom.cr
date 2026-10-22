require "proc"
callback = Proc(NoReturn).new do
  nested = -> { return 65_i32 }
  nested.call
end
callback.call
