require "proc"

callback = Proc(Tuple(Int32, Int32), Int32).new do |(same, same)|
  same
end
callback.call({65_i32, 66_i32})
