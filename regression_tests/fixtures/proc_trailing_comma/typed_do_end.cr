lib Native
  fun putchar(c : Int32) : Int32
end
fn = ->(
 x : Int32,
) do
 Native.putchar(x)
end
fn.call(65)
