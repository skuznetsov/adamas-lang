require "proc"
lib MacroUnpackCallerLocalOutput
  fun putchar(value : Int32) : Int32
end
macro execute_pair_and_preserve_caller_locals(&block)
  {{block.args[0]}} = {65_i32, 66_i32}
  {{block.body}}
end
def run_pair_and_preserve_caller_locals
  caller_sentinel_left = 80_i32
  caller_sentinel_right = 81_i32
  execute_pair_and_preserve_caller_locals do |(left, right)|
    MacroUnpackCallerLocalOutput.putchar(left)
    MacroUnpackCallerLocalOutput.putchar(right)
  end
  MacroUnpackCallerLocalOutput.putchar(caller_sentinel_left)
  MacroUnpackCallerLocalOutput.putchar(caller_sentinel_right)
end
run_pair_and_preserve_caller_locals
MacroUnpackCallerLocalOutput.putchar(10_i32)
