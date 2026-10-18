lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar({{ "65".to_i(nil) }})
