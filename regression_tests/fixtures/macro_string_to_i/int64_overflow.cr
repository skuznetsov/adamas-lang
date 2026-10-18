lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar({{ "9223372036854775808".to_i }})
