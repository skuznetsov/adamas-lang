require "proc"
callback = Proc(Int32).new do
  nested = -> { return "wrong" }
  nested.call
end
callback.call
