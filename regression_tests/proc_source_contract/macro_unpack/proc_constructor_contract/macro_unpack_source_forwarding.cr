require "proc"
lib MacroSourceForwardingOutput
  fun putchar(value : Int32) : Int32
end
def apply_pair(&block)
  yield({65_i32, 66_i32})
end
macro call_pair(&block)
  apply_pair {{block}}
end
call_pair do |(left, right)|
  MacroSourceForwardingOutput.putchar(left)
  MacroSourceForwardingOutput.putchar(right)
end
MacroSourceForwardingOutput.putchar(10_i32)
