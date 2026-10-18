lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar({{ 'A'.to_i }})
