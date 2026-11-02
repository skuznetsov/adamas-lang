lib LibC
  fun putchar(value : Int32) : Int32
end

macro publish_proc_name
  def __crystal_proc_0 : Int32
    2
  end
end

publish_proc_name

if __crystal_proc_0 == 2
  LibC.putchar(65_i32)
else
  LibC.putchar(66_i32)
end
LibC.putchar(10_i32)
