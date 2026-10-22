require "proc"

callback = Proc(Tuple(Int32), Int32).new do |(first, second)|
  first
end
callback.call({65_i32})
