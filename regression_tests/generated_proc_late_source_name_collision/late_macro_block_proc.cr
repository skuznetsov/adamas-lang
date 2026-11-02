lib LibC
  fun putchar(value : Int32) : Int32
end

def save_block(&block : -> Int32) : Proc(Int32)
  block
end

callback = save_block { 1 }

macro publish_block_proc_name
  def __crystal_block_proc_0 : Int32
    2
  end
end

publish_block_proc_name

source_value = __crystal_block_proc_0
callback_value = callback.call

if source_value == 2
  LibC.putchar(65_i32)
else
  LibC.putchar(66_i32)
end
if callback_value == 1
  LibC.putchar(67_i32)
else
  LibC.putchar(68_i32)
end
LibC.putchar(10_i32)
