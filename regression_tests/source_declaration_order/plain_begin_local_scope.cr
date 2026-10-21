lib LibC
  fun putchar(value : Int32) : Int32
end

value = 65_i32
begin
  value = 66_i32
  begin
    value = 67_i32
  end
end
LibC.putchar(value)
