lib Native
 fun putchar(c : Int32) : Int32
end
value = Int32
Native.putchar(value.is_a?(Int32?) ? 66 : 65)
